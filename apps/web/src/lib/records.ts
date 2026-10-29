import { readdirSync } from "node:fs";

import { CATALOGUE, DATA, INVENTORY, NOTES } from "./paths";

export type Value = string | number | string[] | null;

export type Field = {
  value: Value;
  source: string | null;
  candidates: Record<string, Value>;
};

export type RymLink = { name: string; id: number; url: string };

export type Rating = { value: number; count: number; scale: number; as_of: string | null };

export type AlbumRecord = {
  slug: string;
  path: string;
  state: "processed";
  edition_choice: { release: string; how: string };
  album: Record<string, Field> & {
    ids: Record<string, Value>;
    ratings: Record<string, Rating>;
    links: { label: string; url: string }[];
    rym_links: {
      artists: RymLink[];
      primary: RymLink[];
      secondary: RymLink[];
      scenes: RymLink[];
    } | null;
  };
  tracks: {
    file: string;
    duration: number;
    fields: Record<string, Field>;
  }[];
};

export type CoverCandidate = {
  id: string;
  source: string;
  path: string;
  types: string[];
  note: string;
  width: number;
  height: number;
  bytes: number;
};

export type CoverChoice = {
  chosen: CoverCandidate;
  why: string;
  master: string;
  master_bytes: number;
  master_method: string;
  embed: string;
  embed_bytes: number;
  embed_size: [number, number];
};

const SKIP = new Set(["editions.json", "covers.json"]);

async function readJson<T>(path: string, fallback: T): Promise<T> {
  const file = Bun.file(path);
  return (await file.exists()) ? ((await file.json()) as T) : fallback;
}

export async function processed(): Promise<Map<string, AlbumRecord>> {
  const out = new Map<string, AlbumRecord>();
  for (const name of readdirSync(CATALOGUE)) {
    if (!name.endsWith(".json") || SKIP.has(name)) continue;
    const rec = await readJson<AlbumRecord | null>(`${CATALOGUE}/${name}`, null);
    if (rec) out.set(rec.path, rec);
  }
  return out;
}

export function coverChoices(): Promise<Record<string, CoverChoice>> {
  return readJson(`${CATALOGUE}/covers.json`, {});
}

export function coverCandidates(slug: string): Promise<CoverCandidate[]> {
  return readJson(`${DATA}/raw/${slug}/covers/candidates.json`, []);
}

export function redCopies(): Promise<Record<string, string[]>> {
  return readJson(`${INVENTORY}/music-red.json`, {});
}

export type Note = { at: string; album: string; by: string; text: string };

export async function notesFor(album: string): Promise<Note[]> {
  const file = Bun.file(NOTES);
  if (!(await file.exists())) return [];
  const lines = (await file.text()).split("\n").filter(Boolean);
  return lines
    .map((l) => JSON.parse(l) as Note)
    .filter((n) => n.album === album);
}


export async function addNote(note: Note): Promise<void> {
  const file = Bun.file(NOTES);
  const before = (await file.exists()) ? await file.text() : "";
  await Bun.write(NOTES, `${before}${JSON.stringify(note)}\n`);
}
