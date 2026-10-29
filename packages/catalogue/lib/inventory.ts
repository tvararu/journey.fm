import { Database } from "bun:sqlite";

import { INV } from "./paths";

export type InvFile = { relpath: string; duration: number; tags: Record<string, string> };

export const inventory = (): Database => new Database(`${INV}/inventory.sqlite`, { readonly: true });

export function files(path: string): InvFile[] {
  const db = inventory();
  const rows = db
    .query<{ id: number; relpath: string; duration: number }, [string]>(
      "select f.id, f.relpath, f.duration from files f join albums a on a.id = f.album_id where a.path = ? order by f.relpath",
    )
    .all(path);
  const tagq = db.query<{ k: string; value: string }, [number]>("select upper(key) k, value from tags where file_id = ?");
  return rows.map((r) => ({
    relpath: r.relpath,
    duration: r.duration,
    tags: Object.fromEntries(tagq.all(r.id).map((t) => [t.k, t.value])),
  }));
}
