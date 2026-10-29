import { existsSync, readFileSync } from "node:fs";

import { CATALOGUE, META, RAW } from "./lib/paths";

type Cand = { id: string; source: string; path: string; types: string[]; width: number; height: number };

const TILE = 360;
const FONT = process.env["SHEET_FONT"] ?? ["/System/Library/Fonts/Supplemental/Arial.ttf", "/usr/share/fonts/TTF/DejaVuSans.ttf"].find(existsSync);
const slug = Bun.argv[2];
if (!slug) {
  console.error("usage: sheet <slug>");
  process.exit(1);
}
const covers = JSON.parse(readFileSync(`${CATALOGUE}/covers.json`, "utf8")) as Record<string, { master: string; chosen: Cand }>;
const cands = JSON.parse(readFileSync(`${RAW}/${slug}/covers/candidates.json`, "utf8")) as Cand[];
const master = covers[slug];

async function thumb(path: string): Promise<Uint8Array> {
  const p = Bun.spawn(["ffmpeg", "-nostdin", "-v", "error", "-i", path, "-vf", "scale=24:24:flags=area,format=gray", "-frames:v", "1", "-f", "rawvideo", "-"], {
    stderr: "ignore", stdout: "pipe",
  });
  return new Uint8Array(await new Response(p.stdout).arrayBuffer());
}
function diff(a: Uint8Array, b: Uint8Array): number {
  if (a.length !== b.length || !a.length) return Infinity;
  const z = (v: Uint8Array) => {
    const m = v.reduce((x, y) => x + y, 0) / v.length;
    const sd = Math.sqrt(v.reduce((x, y) => x + (y - m) ** 2, 0) / v.length) || 1;
    return [...v].map((x) => (x - m) / sd);
  };
  const x = z(a);
  const y = z(b);
  let s = 0;
  for (let i = 0; i < x.length; i++) s += Math.abs(x[i]! - y[i]!);
  return s / x.length;
}

const shown = cands
  .map((c, i) => ({ c, i }))
  .filter(({ c }) => !c.source.startsWith("Upscaled") && (c.types.includes("Front") || !c.types.length) && c.id !== master?.chosen.id)
  .sort((x, y) => y.c.width * y.c.height - x.c.width * x.c.height)
  .slice(0, master ? 7 : 8);
const ref = master ? await thumb(`${META}/${master.master}`) : null;
const tiles: { path: string; label: string }[] = [];
if (master) tiles.push({ label: `MASTER ${master.chosen.source} ${master.chosen.width}x${master.chosen.height}`, path: `${META}/${master.master}` });
const legend: string[] = master ? [`tile 0: MASTER = candidate ${cands.findIndex((c) => c.id === master.chosen.id)} (${master.chosen.source} ${master.chosen.width}x${master.chosen.height})`] : [];
for (const { c, i } of shown) {
  const d = ref ? diff(ref, await thumb(`${META}/${c.path}`)) : NaN;
  const art = Number.isFinite(d) ? (d <= 0.35 ? `same art (${d.toFixed(2)})` : `different (${d.toFixed(2)})`) : "";
  tiles.push({ label: `#${i} ${c.source.replace("Cover Art Archive", "CAA")} ${c.width}x${c.height} ${art}`, path: `${META}/${c.path}` });
  legend.push(`tile ${tiles.length - 1}: candidate ${i}  ${c.source} ${c.width}x${c.height} ${c.types.join("+") || "-"}  ${art}  id ${c.id}`);
}
if (!tiles.length) {
  console.log("no cover candidates");
  process.exit(0);
}

const cols = Math.min(4, tiles.length);
const rows = Math.ceil(tiles.length / cols);
const esc = (s: string) => s.replace(/[\\:']/g, (c) => `\\${c}`);
const parts = tiles.map((t, k) => {
  const text = FONT ? `,drawbox=y=ih-28:w=iw:h=28:color=black@0.7:t=fill,drawtext=fontfile=${esc(FONT)}:text='${esc(t.label)}':x=6:y=h-21:fontsize=14:fontcolor=white` : "";
  return `[${k}:v]scale=${TILE}:${TILE}:force_original_aspect_ratio=decrease,pad=${TILE}:${TILE}:(ow-iw)/2:(oh-ih)/2:color=gray${text}[t${k}]`;
});
const layout = tiles.map((_, k) => `${(k % cols) * TILE}_${Math.floor(k / cols) * TILE}`).join("|");
const filter = `${parts.join(";")};${tiles.map((_, k) => `[t${k}]`).join("")}xstack=inputs=${tiles.length}:layout=${layout}:fill=black[out]`;
const out = `${RAW}/${slug}/covers/sheet.jpg`;
const inputs = tiles.flatMap((t) => ["-i", t.path]);
const p = Bun.spawnSync(["ffmpeg", "-nostdin", "-v", "error", "-y", ...inputs, "-filter_complex", filter, "-map", "[out]", "-frames:v", "1", "-q:v", "4", out], { stderr: "pipe" });
if (p.exitCode !== 0) throw new Error(p.stderr.toString().slice(-500));
console.log(`${out}  (${cols}x${rows} tiles of ${TILE} px; view it with the Read tool)`);
console.log(legend.join("\n"));
