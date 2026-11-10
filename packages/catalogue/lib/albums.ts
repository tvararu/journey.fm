import { existsSync, readdirSync } from "node:fs";

import { files, inventory } from "./inventory";
import { CATALOGUE, RAW } from "./paths";
import { squash } from "./py";

export type Album = { path: string; slug: string; artist: string; title: string };

const shortSlug = (path: string): string => {
  const [, artistDir = "", albumDir = ""] = path.split("/");
  return `${squash(artistDir).slice(0, 12)}-${squash(albumDir).slice(0, 16)}`;
};

let shared: Set<string> | null = null;

export function slugOf(path: string): string {
  if (!shared) {
    const seen = new Set<string>();
    shared = new Set();
    for (const p of libraryPaths()) {
      const s = shortSlug(p);
      if (seen.has(s)) shared.add(s);
      seen.add(s);
    }
  }
  const s = shortSlug(path);
  return shared.has(s) ? `${s}-${new Bun.CryptoHasher("sha1").update(path).digest("hex").slice(0, 4)}` : s;
}

export function albumOf(path: string): Album {
  const [, artistDir = "", albumDir = ""] = path.split("/");
  const fs = files(path);
  if (!fs.length) throw new Error(`no files in the inventory for ${path}`);
  const t = fs[0]!.tags;
  return {
    artist: t["ALBUMARTIST"] || t["ARTIST"] || artistDir,
    path,
    slug: slugOf(path),
    title: t["ALBUM"] || albumDir,
  };
}

const YEAR_KEYS = ["ORIGINALDATE", "ORIGINALYEAR", "DATE"];

export function yearOf(tags: Record<string, string>): number | null {
  for (const k of YEAR_KEYS) {
    const m = tags[k]?.match(/\d{4}/);
    if (m) return Number(m[0]);
  }
  return null;
}

export function yearsOf(paths: string[]): Map<string, number | null> {
  const rows = inventory()
    .query<{ path: string; relpath: string; k: string; value: string }, []>(
      `select a.path, f.relpath, upper(t.key) k, t.value from albums a join files f on f.album_id = a.id join tags t on t.file_id = f.id where upper(t.key) in ('ORIGINALDATE', 'ORIGINALYEAR', 'DATE') order by a.path, f.relpath`,
    )
    .all();
  const wanted = new Set(paths);
  const first = new Map<string, string>();
  const tags = new Map<string, Record<string, string>>();
  for (const r of rows) {
    if (!wanted.has(r.path)) continue;
    if (!first.has(r.path)) first.set(r.path, r.relpath);
    if (first.get(r.path) !== r.relpath) continue;
    (tags.get(r.path) ?? tags.set(r.path, {}).get(r.path)!)[r.k] = r.value;
  }
  return new Map(paths.map((p) => [p, yearOf(tags.get(p) ?? {})]));
}

export function chronological(paths: string[]): string[] {
  const years = yearsOf(paths);
  const key = (p: string) => p.split("/")[1] ?? "";
  return [...paths].sort(
    (a, b) =>
      key(a).localeCompare(key(b)) ||
      (years.get(a) ?? Infinity) - (years.get(b) ?? Infinity) ||
      (a < b ? -1 : a > b ? 1 : 0),
  );
}

export const libraryPaths = (): string[] =>
  inventory().query<{ path: string }, []>("select path from albums where path like 'Music/%' order by path").all().map((r) => r.path);

export const catalogued = (slug: string): boolean => existsSync(`${CATALOGUE}/${slug}.json`);

export const rymGrabbed = (slug: string): boolean =>
  existsSync(`${RAW}/${slug}`) && readdirSync(`${RAW}/${slug}`).some((n) => /^rym-\d{4}-\d{2}-\d{2}\.json$/.test(n));
