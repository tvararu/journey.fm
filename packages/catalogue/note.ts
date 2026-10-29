import { Database } from "bun:sqlite";
import { appendFileSync } from "node:fs";

const NOTES = `${import.meta.dir}/../notes.jsonl`;
const args = Bun.argv.slice(2);
function flag(name: string, fallback: string): string {
  const at = args.indexOf(name);
  return at >= 0 ? (args.splice(at, 2)[1] ?? fallback) : fallback;
}
const by = flag("--by", "claude");
const kind = flag("--kind", "note") === "instruction" ? "instruction" : "note";
const [query, ...rest] = args;
const text = rest.join(" ").trim();
if (!(query && text)) {
  console.error('usage: music:note <album id | slug | text in its path> "<note>" [--by deity] [--kind instruction]');
  process.exit(1);
}

const editions = (await Bun.file(`${import.meta.dir}/../data/catalogue/editions.json`).json()) as Record<string, { path: string }>;
const db = new Database(`${import.meta.dir}/../data/inventory/inventory.sqlite`, { readonly: true });
type Row = { path: string };
const rows = /^\d+$/.test(query)
  ? db.query<Row, [number]>("select path from albums where id = ?").all(Number(query))
  : db.query<Row, [string]>("select path from albums where path like ?").all(`%${editions[query]?.path ?? query}%`);

if (rows.length !== 1) {
  console.error(rows.length ? "Several albums match, use the id:" : "No album matches.");
  for (const r of rows) console.error(`  ${r.path}`);
  process.exit(1);
}

const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
const entry = { album: rows[0]?.path, at, by, kind, text };
appendFileSync(NOTES, `${JSON.stringify(entry)}\n`);
console.log(`noted on ${entry.album}`);
