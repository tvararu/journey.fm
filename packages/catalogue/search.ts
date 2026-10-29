import { Database } from "bun:sqlite";

const term = Bun.argv.slice(2).join(" ");
if (!term) {
  console.error("usage: music:search <text>");
  process.exit(1);
}

const db = new Database(`${import.meta.dir}/../data/inventory/inventory.sqlite`, { readonly: true });
const like = `%${term}%`;

const byPath = db
  .query<{ id: number; path: string; n: number }, [string]>(
    `select a.id, a.path, count(f.id) n from albums a join files f on f.album_id = a.id
    where a.path like ? group by a.id order by a.path`,
  )
  .all(like);

const byTag = db
  .query<{ id: number; path: string; key: string; value: string; n: number }, [string]>(
    `select a.id, a.path, t.key, t.value, count(*) n from tags t join files f on f.id = t.file_id
    join albums a on a.id = f.album_id where t.value like ? group by a.id, t.key, t.value order by a.path, t.key limit 200`,
  )
  .all(like);

console.log(`Folders matching "${term}": ${byPath.length}`);
for (const r of byPath) console.log(`  ${String(r.id).padStart(4)}  ${r.path}  (${r.n} files)`);
console.log(`\nTag values matching "${term}": ${byTag.length}${byTag.length === 200 ? "+" : ""}`);
for (const r of byTag) {
  const v = r.value.length > 80 ? `${r.value.slice(0, 80)}…` : r.value;
  console.log(`  ${String(r.id).padStart(4)}  ${r.path}  ${r.key}=${v}  ×${r.n}`);
}
