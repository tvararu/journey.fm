import { readdirSync, statSync } from "node:fs";

import { DATA } from "./paths";
import type { AlbumRecord } from "./records";

export type RawFile = {
  name: string;
  bytes: number;
  fetched: string | null;
  used: boolean;
};

const LABELS: [RegExp, string][] = [
  [/^mb_release_/, "MusicBrainz release"],
  [/^mb_rg_releases_/, "MusicBrainz release list"],
  [/^mb_rg_/, "MusicBrainz release group"],
  [/^mb_discid/, "MusicBrainz disc ID lookup"],
  [/^rym-/, "RYM page"],
  [/^red_riplog_/, "RED rip log"],
  [/^red_torrent_/, "RED torrent"],
  [/^red_group_/, "RED group"],
  [/^discogs_release_/, "Discogs release"],
  [/^discogs_master_/, "Discogs master"],
  [/^caa_release_/, "Cover Art Archive (release)"],
  [/^caa_rg_/, "Cover Art Archive (release group)"],
  [/^edition-report/, "Edition match report"],
];

export function label(name: string): string {
  return LABELS.find(([re]) => re.test(name))?.[1] ?? "Spike lookup (search-based, may be another edition)";
}

async function fetchedAt(path: string): Promise<string | null> {
  if (!path.endsWith(".json")) return null;
  try {
    const d = (await Bun.file(path).json()) as { fetched?: string } | null;
    return d && typeof d === "object" && typeof d.fetched === "string" ? d.fetched.slice(0, 16).replace("T", " ") : null;
  } catch {
    return null;
  }
}

export async function rawFiles(rec: AlbumRecord): Promise<RawFile[]> {
  const dir = `${DATA}/raw/${rec.slug}`;
  const ids = Object.values(rec.album.ids)
    .flat()
    .filter((v) => v !== null)
    .map(String);
  ids.push(rec.edition_choice.release);
  const out: RawFile[] = [];
  for (const name of readdirSync(dir).sort()) {
    const st = statSync(`${dir}/${name}`);
    if (st.isDirectory()) continue;
    const used = name.startsWith("rym-") || name.startsWith("edition-report") || ids.some((id) => id.length > 3 && name.includes(id));
    out.push({ bytes: st.size, fetched: await fetchedAt(`${dir}/${name}`), name, used });
  }
  return out;
}
