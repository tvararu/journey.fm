import { existsSync, readFileSync } from "node:fs";

import { album as lookupAcoustid, prints } from "./acoustid";
import { edition as runEdition } from "./edition";
import { enrich } from "./enrich";
import { files } from "./lib/inventory";
import { CATALOGUE, META, RAW } from "./lib/paths";
import { squash } from "./lib/py";
import { load } from "./lib/raw";

type Candidate = { how: string; id: string; date: string | null; evidence: string[]; lengths: string };
type Cover = { id: string; source: string; types: string[]; width: number; height: number };
type Release = { media: { tracks?: { recording?: { id: string } }[] }[] };
type Album = { path: string; slug: string; artist: string; title: string; log: string[] };

const HERE = `${import.meta.dir}/..`;
const MUSIC = `${HERE}/..`;
const PREVIEWS = `${HERE}/../../../tmp/music-covers`;
const SOL_BUN = "/home/user/.local/share/mise/installs/bun/latest/bin/bun";
const COVER_TIERS = [
  "Cover Art Archive (release)", "Cover Art Archive (same catalogue number)", "Cover Art Archive (release group)",
  "iTunes", "Deezer", "files (folder)", "files (embedded)",
];

const paths = Bun.argv.slice(2);
if (!paths.length) {
  console.error('usage: music:prepare "Music/Artist/Album" ...');
  process.exit(1);
}

function run(cmd: string[], cwd = HERE): string {
  const p = Bun.spawnSync(cmd, { cwd, stderr: "pipe", stdout: "pipe" });
  if (p.exitCode !== 0) throw new Error(`${cmd.slice(0, 3).join(" ")} failed: ${p.stderr.toString().slice(-600)}`);
  return p.stdout.toString();
}

async function runAsync(cmd: string[], cwd = HERE): Promise<{ code: number; out: string }> {
  const p = Bun.spawn(cmd, { cwd, stderr: "pipe", stdout: "pipe" });
  const [out, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
  return { code, out: out + err };
}

const albums: Album[] = paths.map((path) => {
  const [, artistDir = "", albumDir = ""] = path.split("/");
  const fs = files(path);
  if (!fs.length) throw new Error(`no files in the inventory for ${path}`);
  const t = fs[0]!.tags;
  return {
    artist: t["ALBUMARTIST"] || t["ARTIST"] || artistDir,
    log: [],
    path,
    slug: `${squash(artistDir).slice(0, 12)}-${squash(albumDir).slice(0, 16)}`,
    title: t["ALBUM"] || albumDir,
  };
});
const say = (a: Album, line: string) => {
  a.log.push(line);
  console.log(`${a.slug}: ${line}`);
};

function fingerprints(): void {
  run(["rsync", "-a", "sol:/mnt/pool/music-meta/fingerprints/", `${META}/fingerprints/`]);
  const have = prints();
  const missing = albums.filter((a) => files(a.path).some((f) => !have.has(`${a.path}/${f.relpath}`)));
  if (!missing.length) return;
  run(["scp", "-q", `${MUSIC}/tagging/fingerprint.ts`, "sol:catalogue/fingerprint.ts"]);
  const q = (x: string) => `'${x.replaceAll("'", "'\\''")}'`;
  const script = `cd ~/catalogue && ${SOL_BUN} fingerprint.ts /mnt/pool/music-meta/fingerprints/music.jsonl ${missing.map((a) => q(a.path)).join(" ")}\n`;
  const p = Bun.spawnSync(["ssh", "sol", "bash", "-s"], { stdin: Buffer.from(script), stderr: "pipe", stdout: "pipe" });
  if (p.exitCode !== 0) throw new Error(`fingerprinting on sol failed: ${p.stderr.toString().slice(-400)}`);
  run(["rsync", "-a", "sol:/mnt/pool/music-meta/fingerprints/", `${META}/fingerprints/`]);
}

async function rym(): Promise<void> {
  for (const a of albums) {
    const found = await runAsync(["bun", `${MUSIC}/tagging/rym-find.ts`, a.artist, a.title]);
    const url = (JSON.parse(found.out.trim().split("\n").at(-1) || "{}") as { url?: string | null }).url;
    if (!url) {
      say(a, `RYM: no exact match for "${a.artist} - ${a.title}"; grab it by hand`);
      continue;
    }
    const grab = await runAsync(["bash", `${MUSIC}/tagging/rym-album.sh`, a.slug, url]);
    const flags = grab.out.match(/CHALLENGE|NOT LOGGED IN/g);
    say(a, flags ? `RYM: ${flags.join(", ")} at ${url}` : `RYM: ${url}`);
  }
}

function acoustidHits(slug: string, rid: string): [number, number] {
  const rel = load(slug, `mb_release_${rid}`) as Release | null;
  const ac = (load(slug, "acoustid") ?? {}) as Record<string, { score: number; recordings: string[] }[] | null>;
  const recs = new Set((rel?.media ?? []).flatMap((m) => (m.tracks ?? []).map((t) => t.recording?.id)));
  const heard = Object.values(ac).filter((m): m is NonNullable<typeof m> => !!m?.length);
  const hits = heard.filter((ms) => ms.some((m) => m.score >= 0.8 && m.recordings.some((r) => recs.has(r))));
  return [hits.length, heard.length];
}

async function edition(a: Album): Promise<boolean> {
  const [, looked] = await Promise.all([runEdition(a.slug, a.path), lookupAcoustid(a.slug, a.path)]);
  if (looked.missing.length) say(a, `AcoustID: no fingerprint for ${looked.missing.length} files`);
  const report = load(a.slug, "edition-report") as { candidates: Candidate[]; red?: { year?: number } } | null;
  const cands = report?.candidates ?? [];
  if (!cands.length) {
    say(a, "edition: no candidates; needs a release picked by hand");
    return false;
  }
  const scored = cands.map((c) => {
    const [hit, of] = acoustidHits(a.slug, c.id);
    const ev = [...c.evidence, ...(of && hit === of ? [`AcoustID ${hit}/${of}`] : [])];
    return { ...c, ev, hit, of };
  });
  const tagged = files(a.path)[0]!.tags["MUSICBRAINZ_ALBUMID"];
  const rank = (c: (typeof scored)[number]) =>
    [c.ev.length, c.hit, Number(c.id === tagged), Number(c.how === "discid"), Number(c.ev.includes("RED year"))];
  const cmp = (x: number[], y: number[]) => x.reduce((d, v, i) => d || y[i]! - v, 0);
  scored.sort((x, y) => cmp(rank(x), rank(y)));
  const best = scored[0]!;
  const tied = scored.filter((c) => c !== best && c.ev.length === best.ev.length && c.hit === best.hit);
  const breaker = tied.length
    ? `; tied on evidence with ${tied.map((c) => `${c.id.slice(0, 8)} (${c.date ?? "?"})`).join(", ")}, broken by ${
        best.id === tagged ? "the files' MusicBrainz tag" : best.how === "discid" ? "disc ID order" : "RED year"
      }`
    : "";
  const why = `auto-picked: ${best.ev.join(", ") || "no evidence"}; ${best.lengths}${breaker}`;
  await enrich(a.slug, a.path, best.id, why);
  say(a, `edition: ${best.id} (${best.date ?? "?"}) ${why}`);
  return true;
}

async function cover(a: Album): Promise<void> {
  const cands = JSON.parse(readFileSync(`${RAW}/${a.slug}/covers/candidates.json`, "utf8")) as Cover[];
  const fronts = cands.filter((c) =>
    COVER_TIERS.includes(c.source) && (c.types.includes("Front") || !c.types.length) &&
    Math.max(c.width, c.height) / Math.min(c.width, c.height) <= 1.2);
  fronts.sort((x, y) => COVER_TIERS.indexOf(x.source) - COVER_TIERS.indexOf(y.source) || y.width * y.height - x.width * x.height);
  const c = fronts[0];
  if (!c) {
    say(a, "cover: no front candidate; pick one by hand");
    return;
  }
  const { out } = await runAsync(["bun", "scripts/covers.ts", "choose", a.slug, c.id, `auto-picked: ${c.source} front, ${c.width}x${c.height}`]);
  say(a, `cover: ${c.source} ${c.width}x${c.height}${out.includes("upscaling") ? ", upscaling to master" : ""}`);
}

async function upscalesDone(started: number): Promise<void> {
  for (let i = 0; i < 60; i++) {
    const pending = albums.filter((a) => {
      const log = `${RAW}/${a.slug}/covers/upscale.log`;
      const covers = JSON.parse(readFileSync(`${CATALOGUE}/covers.json`, "utf8")) as Record<string, { chosen: Cover }>;
      const small = covers[a.slug] && Math.max(covers[a.slug]!.chosen.width, covers[a.slug]!.chosen.height) < 2000;
      return small && !(existsSync(log) && Bun.file(log).lastModified >= started && readFileSync(log, "utf8").trim());
    });
    if (!pending.length) return;
    await Bun.sleep(5000);
  }
  console.log("some upscales are still running; their resolve runs when they finish");
}

const started = Date.now();
fingerprints();
const rymDone = rym();
const ok: Album[] = [];
await Promise.all(albums.map(async (a) => {
  try {
    if (!(await edition(a))) return;
    const r = await runAsync(["bun", "scripts/covers.ts", PREVIEWS, a.slug]);
    if (r.code !== 0) say(a, `covers failed: ${r.out.slice(-400)}`);
    else await cover(a);
    ok.push(a);
  } catch (e) {
    say(a, `failed: ${(e as Error).message}`);
  }
}));
run(["bun", "scripts/resolve.ts"]);
await Promise.all(ok.map(async (a) => {
  const ly = await runAsync(["bun", "scripts/lyrics.ts", a.slug]);
  const lines = ly.out.split("\n").filter((l) => l.startsWith(`${a.slug} `));
  const count = (k: string) => lines.filter((l) => l.includes(`-> ${k}`)).length;
  say(a, `lyrics: ${count("synced")} synced, ${count("plain")} plain, ${count("instrumental")} instrumental, ${count("missing")} missing${
    count("failed") ? `, ${count("failed")} failed (rerun music:lyrics)` : ""}`);
}));
await rymDone;
await upscalesDone(started);
run(["bun", "scripts/resolve.ts"]);
for (const a of ok) {
  const rec = JSON.parse(readFileSync(`${CATALOGUE}/${a.slug}.json`, "utf8")) as { tracks: { ids: { acoustid_agrees?: boolean | null } }[] };
  const agree = rec.tracks.map((t) => t.ids.acoustid_agrees);
  say(a, `AcoustID: ${agree.filter((x) => x === true).length} agree, ${agree.filter((x) => x === false).length} differ, ${
    agree.filter((x) => x == null).length} unknown`);
}
console.log("\nprepared:", ok.map((a) => a.slug).join(" ") || "none");
