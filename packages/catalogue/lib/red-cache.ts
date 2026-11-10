import { existsSync, readFileSync } from "node:fs";

import { RAW } from "./paths";
import { load } from "./raw";

export type Torrent = {
  id: number;
  media: string;
  encoding: string;
  filePath?: string | null;
  remasterYear?: number | null;
  remasterTitle?: string | null;
  remasterRecordLabel?: string | null;
  remasterCatalogueNumber?: string | null;
};
export type Group = { group: { id: number; name: string }; torrents: Torrent[] };
export type RedMatch = { fetched: string; dirs: string[]; group: number | null; torrent: number | null; logs: number[] };
export type RedCopy = { match: RedMatch; group: Group; torrent: Torrent; logs: string[] };

export const cachedRed = (slug: string): RedMatch | null => load(slug, "red-match") as RedMatch | null;

export function redCopy(slug: string, match: RedMatch): RedCopy | null {
  if (!match.group || !match.torrent) return null;
  const group = load(slug, `red_group_${match.group}`) as Group;
  const torrent = group.torrents.find((t) => t.id === match.torrent)!;
  const logs = match.logs.map((l) => `${RAW}/${slug}/red_riplog_${match.torrent}_${l}.log`).filter(existsSync).map((p) => readFileSync(p, "utf8"));
  return { match, group, torrent, logs };
}
