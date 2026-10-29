import { existsSync, readFileSync } from "node:fs";

import { files } from "./lib/inventory";
import { CATALOGUE, META, RAW } from "./lib/paths";
import { squash } from "./lib/py";
import { load } from "./lib/raw";

type J = any;
const slug = Bun.argv[2];
if (!slug) {
  console.error("usage: music:inspect <slug>");
  process.exit(1);
}
const editions = JSON.parse(readFileSync(`${CATALOGUE}/editions.json`, "utf8")) as Record<string, J>;
const choice = editions[slug];
if (!choice) throw new Error(`no edition chosen for ${slug}`);
const rec = JSON.parse(readFileSync(`${CATALOGUE}/${slug}.json`, "utf8")) as J;
const report: J = load(slug, "edition-report") ?? {};
const covers = JSON.parse(readFileSync(`${CATALOGUE}/covers.json`, "utf8")) as Record<string, J>;
const show = (v: unknown): string => (v == null ? "-" : Array.isArray(v) ? v.join("; ") : typeof v === "object" ? JSON.stringify(v) : String(v));
const same = (a: unknown, b: unknown) => squash(show(a)) === squash(show(b));
const out: string[] = [];
const line = (s = "") => out.push(s);

const labels = (r: J) => (r?.["label-info"] ?? []).map((l: J) => `${l.label?.name ?? "?"} ${l["catalog-number"] ?? ""}`.trim()).join(", ") || "-";
const rel: J = load(slug, `mb_release_${choice.release}`);
line(`${choice.path}  (${slug})`);
line(`EDITION ${choice.release}  ${rel?.date ?? "?"} ${rel?.country ?? "?"} ${rel?.status ?? "?"} ${(rel?.media ?? []).map((m: J) => m.format).join("+")}  ${labels(rel)}  barcode ${rel?.barcode || "-"}`);
line(`  why: ${choice.how}`);
const red = report.red;
line(red
  ? `  RED: torrent ${red.torrent}, ${red.media}, ${red.year ?? "?"}, ${red.label || "no label"} ${red.catno || "no catno"}${red.title ? `, "${red.title}"` : ""}`
  : "  RED: no torrent matched");
const fs = files(choice.path);
const tagged = fs[0]?.tags["MUSICBRAINZ_ALBUMID"];
line(`  files tagged: ${tagged ? `${tagged}${tagged === choice.release ? " (this release)" : " (a different release)"}` : "no MusicBrainz release"}`);
for (const c of report.candidates ?? []) {
  const r: J = load(slug, `mb_release_${c.id}`);
  const mark = c.id === choice.release ? "*" : " ";
  line(`  ${mark} ${c.id.slice(0, 8)} ${c.date ?? "?"} ${c.country ?? "?"} ${r?.status ?? "?"} ${c.format}  ${c.labels || "-"}  [${c.evidence.join(", ") || "no evidence"}] ${c.lengths}`);
}

line();
line("FIELDS (value [source]; other sources only where they differ)");
for (const [k, f] of Object.entries(rec.album) as [string, J][]) {
  if (!f || typeof f !== "object" || !("value" in f) || ["cover"].includes(k)) continue;
  const others = Object.entries(f.candidates ?? {}).filter(([, v]) => !same(v, f.value)).map(([s, v]) => `${s}=${show(v)}`);
  line(`  ${k}: ${show(f.value)} [${f.source ?? "-"}]${others.length ? `   differs: ${others.join(" | ")}` : ""}`);
}
const r = rec.album.ratings ?? {};
if (Object.keys(r).length) line(`  ratings: ${Object.entries(r).map(([s, v]: [string, J]) => `${s} ${v.value} (${v.count})`).join(", ")}`);

line();
line(`TRACKS (${rec.tracks.length} in record, ${fs.length} files)`);
for (const t of rec.tracks) {
  const f = t.fields;
  const fileTitle = f.title.candidates.files;
  const mb = f.length.candidates.MusicBrainz;
  const gap = typeof mb === "number" ? Math.abs(mb - f.length.value) : null;
  const ly = f.lyrics;
  const kind = f.instrumental?.value ? "instrumental" : ly?.source === "LRCLIB synced" ? "synced" : ly?.source === "LRCLIB plain" ? "plain" : ly?.value ? "files" : "none";
  const first = typeof ly?.value === "string" ? ly.value.replace(/\[\d+:\d+\.\d+\]\s*/g, "").split("\n").find((x: string) => x.trim())?.slice(0, 50) : "";
  const ac = t.ids.acoustid_agrees === true ? "ac ok" : t.ids.acoustid_agrees === false ? "AC DIFFERS" : "ac ?";
  const credits = ["composer", "lyricist", "performer", "producer", "engineer", "mixer"].filter((k) => f[k]?.value?.length).length;
  line(`  ${String(f.track.value ?? "?").padStart(2)} ${f.title.value}${fileTitle && !same(fileTitle, f.title.value) ? `  (file: ${fileTitle})` : ""}` +
    `  ${f.length.value}s${gap == null ? " (no MB track)" : gap > 2 ? ` MB ${mb}s GAP` : ""}  ${ac}  ${kind}${first ? `: ${first}` : ""}  credits:${credits}`);
}
const paired = new Set(rec.tracks.map((t: J) => t.file));
const extra = fs.filter((f) => !paired.has(f.relpath));
if (extra.length) line(`  files not in record: ${extra.map((f) => f.relpath).join(", ")}`);

line();
const cv = covers[slug];
line(`COVER master: ${cv ? `${cv.chosen.source} ${cv.chosen.width}x${cv.chosen.height} -> ${cv.master_method}` : "none chosen"}`);
if (cv) line(`  why: ${cv.why}`);
const cands = existsSync(`${RAW}/${slug}/covers/candidates.json`) ? (JSON.parse(readFileSync(`${RAW}/${slug}/covers/candidates.json`, "utf8")) as J[]) : [];
line(`  candidates: ${cands.length} (see music:sheet ${slug} for a picture)`);
cands.forEach((c, i) => line(`   ${String(i).padStart(2)} ${c.id === cv?.chosen.id ? "*" : " "} ${c.source} ${c.width}x${c.height} ${c.types.join("+") || "-"}${c.note ? `  ${String(c.note).slice(0, 40)}` : ""}`));

const notes = existsSync(`${META}/../notes.jsonl`)
  ? readFileSync(`${META}/../notes.jsonl`, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as J).filter((n) => n.album === choice.path)
  : [];
if (notes.length) {
  line();
  line("NOTES");
  for (const n of notes.slice(-3)) line(`  ${n.at} ${n.by}: ${String(n.text).slice(0, 300)}`);
}
console.log(out.join("\n"));
