import { existsSync, readFileSync } from "node:fs";

import { CATALOGUE, RAW } from "./lib/paths";
import { dump } from "./lib/py";

const [slug, which, set, ...why] = Bun.argv.slice(2);
if (!(slug && which && (set === "instrumental" || set === "none" || set === "clear"))) {
  console.error('usage: music:lyrics-set <slug> <track number | file> instrumental|none|clear ["why"]');
  process.exit(1);
}
const rec = JSON.parse(readFileSync(`${CATALOGUE}/${slug}.json`, "utf8")) as { tracks: { file: string; fields: { track: { value: string } } }[] };
const t = rec.tracks.find((x) => x.file === which || x.fields.track.value === which);
if (!t) throw new Error(`no track ${which} in ${slug}`);
const p = `${RAW}/${slug}/lyrics-overrides.json`;
const all = (existsSync(p) ? (JSON.parse(readFileSync(p, "utf8")) as { data: Record<string, unknown> }).data : {}) as Record<string, unknown>;
if (set === "clear") delete all[t.file];
else all[t.file] = { by: process.env["LYRICS_BY"] ?? "claude", set, why: why.join(" ") };
dump(p, { data: all, fetched: new Date().toISOString() });
console.log(`${slug} ${t.file}: ${set}; run music:resolve`);
