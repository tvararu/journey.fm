import { Database } from "bun:sqlite";
import { readdirSync } from "node:fs";

type Field = { value: unknown; source: string | null };
type AlbumRecord = { slug: string; path: string; album: Record<string, Field> };

const DATA = `${import.meta.dir}/../data`;
const query = Bun.argv.slice(2).join(" ");
if (!query) {
  console.error("usage: music:album <id | slug | text in its path>");
  process.exit(1);
}

const records: AlbumRecord[] = [];
for (const name of readdirSync(`${DATA}/catalogue`)) {
  if (name.endsWith(".json") && name !== "editions.json" && name !== "covers.json") {
    records.push((await Bun.file(`${DATA}/catalogue/${name}`).json()) as AlbumRecord);
  }
}

const db = new Database(`${DATA}/inventory/inventory.sqlite`, { readonly: true });
type Row = { id: number; path: string };
const bySlug = records.find((r) => r.slug === query);
const rows = /^\d+$/.test(query)
  ? db.query<Row, [number]>("select id, path from albums where id = ?").all(Number(query))
  : db.query<Row, [string]>("select id, path from albums where path like ? order by path").all(`%${bySlug?.path ?? query}%`);

if (rows.length !== 1) {
  console.log(rows.length ? "Several albums match, pick one by id:" : "No album matches.");
  for (const r of rows) console.log(`  ${String(r.id).padStart(4)}  ${r.path}`);
  process.exit(rows.length ? 0 : 1);
}

const a = rows[0] as Row;
const files = db
  .query<{ relpath: string; codec: string; bits: number; sample_rate: number; duration: number; id3v2: number }, [number]>(
    "select relpath, codec, bits, sample_rate, duration, id3v2 from files where album_id = ? order by relpath",
  )
  .all(a.id);
const tags = db
  .query<{ key: string; value: string; n: number }, [number]>(
    `select t.key, t.value, count(*) n from tags t join files f on f.id = t.file_id where f.album_id = ?
    group by t.key, t.value order by upper(t.key), n desc`,
  )
  .all(a.id);

console.log(`${a.path}  (album ${a.id}, ${files.length} files)  http://localhost:8787/album/${a.id}\n`);
const notesFile = Bun.file(`${import.meta.dir}/../notes.jsonl`);
const notes = (await notesFile.exists() ? (await notesFile.text()).split("\n").filter(Boolean) : [])
  .map((l) => JSON.parse(l) as { at: string; album: string; by: string; text: string })
  .filter((n) => n.album === a.path);
const reviewsFile = Bun.file(`${import.meta.dir}/../reviews.jsonl`);
const reviews = (await reviewsFile.exists() ? (await reviewsFile.text()).split("\n").filter(Boolean) : [])
  .map((l) => JSON.parse(l) as { at: string; album: string; by: string; verdict: string; message: string })
  .filter((r) => r.album === a.path)
  .map((r) => ({ at: r.at, by: r.by, text: `[${r.verdict === "accept" ? "accepted" : "requested changes"}] ${r.message}` }));
const conversation = [...notes, ...reviews].sort((x, y) => x.at.localeCompare(y.at));
if (conversation.length) {
  console.log("Conversation:");
  for (const n of conversation) console.log(`  ${n.at} ${n.by}: ${n.text}`);
  console.log("");
}
const rec = records.find((r) => r.path === a.path);
if (rec) {
  console.log(`Processed as ${rec.slug}:`);
  for (const [k, f] of Object.entries(rec.album)) {
    if (k === "ids" || k === "rym_links") continue;
    const v = Array.isArray(f.value) ? f.value.join(", ") : String(f.value ?? "-");
    console.log(`  ${k.padEnd(18)} ${v.length > 90 ? `${v.slice(0, 90)}…` : v}  [${f.source ?? ""}]`);
  }
  console.log("");
} else {
  console.log("Not processed yet (triage).\n");
}
const PER_TRACK = /^(TITLE|TRACKNUMBER|ISRC|~LENGTH|.*TRACK ?ID|MUSICBRAINZ_RELEASETRACKID)$/;
console.log("Tags in the files (value ×tracks; per-track titles and IDs left out):");
for (const t of tags) {
  if (t.n === files.length || !PER_TRACK.test(t.key.toUpperCase())) {
    const v = t.value.length > 90 ? `${t.value.slice(0, 90)}…` : t.value;
    console.log(`  ${t.key}=${v}${t.n === files.length ? "" : `  ×${t.n}`}`);
  }
}
console.log("\nFiles:");
for (const f of files) {
  console.log(`  ${f.relpath}  ${f.codec} ${f.bits}/${f.sample_rate}  ${f.duration.toFixed(1)} s${f.id3v2 ? "  ID3" : ""}`);
}
