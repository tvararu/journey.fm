import { existsSync, readdirSync, readFileSync } from "node:fs";

import { files, inventory } from "./inventory";
import { CATALOGUE, RAW, RECORDS } from "./paths";
import { squash } from "./py";

export type Album = { path: string; slug: string; artist: string; title: string };

export const RYM_SKIP = `${RECORDS}/rym-skip.tsv`;

export function slugOf(path: string): string {
  const [, artistDir = "", albumDir = ""] = path.split("/");
  return `${squash(artistDir).slice(0, 12)}-${squash(albumDir).slice(0, 16)}`;
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

export const libraryPaths = (): string[] =>
  inventory().query<{ path: string }, []>("select path from albums where path like 'Music/%' order by path").all().map((r) => r.path);

export const catalogued = (slug: string): boolean => existsSync(`${CATALOGUE}/${slug}.json`);

export const rymGrabbed = (slug: string): boolean =>
  existsSync(`${RAW}/${slug}`) && readdirSync(`${RAW}/${slug}`).some((n) => /^rym-\d{4}-\d{2}-\d{2}\.json$/.test(n));

export const rymSkipped = (): Set<string> =>
  new Set(existsSync(RYM_SKIP) ? readFileSync(RYM_SKIP, "utf8").split("\n").slice(1).filter(Boolean) : []);
