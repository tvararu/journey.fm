import { Database } from "bun:sqlite";

import { INVENTORY } from "./paths";

let conn: Database | null = null;

function db(): Database {
  conn ??= new Database(`${INVENTORY}/inventory.sqlite`, { readonly: true });
  return conn;
}

export type AlbumRow = {
  id: number;
  path: string;
  artist_dir: string;
  album_dir: string;
};

export type LibraryRow = AlbumRow & {
  n: number;
  codec: string;
  bits: string;
  sr: string;
  dur: number;
  id3: number;
  pics: number;
};

export type FileRow = {
  id: number;
  relpath: string;
  size: number;
  codec: string;
  sample_rate: number;
  bits: number;
  channels: number;
  duration: number;
  audio_md5: string | null;
  vendor: string | null;
  id3v2: number | null;
  id3v1: number | null;
  blocks: string | null;
};

export type PictureRow = {
  file_id: number;
  type: number;
  width: number;
  height: number;
  size: number;
  sha256: string;
};

export type ExtraRow = { relpath: string; size: number; sha256: string };

export function libraryRows(): LibraryRow[] {
  return db()
    .query<LibraryRow, []>(
      `select a.id, a.path, a.artist_dir, a.album_dir, count(f.id) n, group_concat(distinct f.codec) codec,
        group_concat(distinct f.bits) bits, group_concat(distinct f.sample_rate) sr, sum(f.duration) dur,
        coalesce(sum(f.id3v2), 0) + coalesce(sum(f.id3v1), 0) id3,
        (select count(*) from pictures p join files f2 on f2.id = p.file_id where f2.album_id = a.id) pics
      from albums a join files f on f.album_id = a.id where a.collection = 'Music' group by a.id order by a.path`,
    )
    .all();
}

export function albumKeyTags(): Map<number, Map<string, Set<string>>> {
  const rows = db()
    .query<{ album_id: number; k: string; value: string }, []>(
      `select f.album_id, upper(t.key) k, t.value from tags t join files f on f.id = t.file_id
      join albums a on a.id = f.album_id where a.collection = 'Music'
      and upper(t.key) in ('ALBUM', 'ALBUMARTIST', 'DATE', 'MUSICBRAINZ_ALBUMID', 'MUSICBRAINZ ALBUM ID')`,
    )
    .all();
  const out = new Map<number, Map<string, Set<string>>>();
  for (const r of rows) {
    const byKey = out.get(r.album_id) ?? new Map<string, Set<string>>();
    byKey.set(r.k, (byKey.get(r.k) ?? new Set()).add(r.value));
    out.set(r.album_id, byKey);
  }
  return out;
}

export function thumbnails(): Map<number, string> {
  const embedded = db()
    .query<{ album_id: number; sha256: string }, []>(
      `select f.album_id, p.sha256, min(p.type != 3) from pictures p join files f on f.id = p.file_id group by f.album_id`,
    )
    .all();
  const folder = db()
    .query<{ album_id: number; sha256: string }, []>(
      `select album_id, sha256 from extras where lower(relpath) like '%.jpg' or lower(relpath) like '%.png' group by album_id`,
    )
    .all();
  return new Map([...folder, ...embedded].map((r) => [r.album_id, r.sha256]));
}

export function album(id: number) {
  const a = db().query<AlbumRow, [number]>("select * from albums where id = ?").get(id);
  if (!a) return null;
  const files = db()
    .query<FileRow, [number]>("select * from files where album_id = ? order by relpath")
    .all(id);
  const tagQuery = db().query<{ key: string; value: string }, [number]>(
    "select key, value from tags where file_id = ? order by idx",
  );
  const tags = new Map(files.map((f) => [f.id, tagQuery.all(f.id)]));
  const pictures = db()
    .query<PictureRow, [number]>(
      "select p.* from pictures p join files f on f.id = p.file_id where f.album_id = ?",
    )
    .all(id);
  const extras = db()
    .query<ExtraRow, [number]>("select relpath, size, sha256 from extras where album_id = ? order by relpath")
    .all(id);
  return { album: a, extras, files, pictures, tags };
}
