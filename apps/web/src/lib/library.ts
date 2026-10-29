import { readdirSync, statSync } from "node:fs";

import { audio } from "./format";
import { albumKeyTags, type LibraryRow, libraryRows, scannedAt, thumbnails } from "./inventory";
import { CATALOGUE, DATA, INVENTORY, NOTES, REVIEWS, VERDICTS } from "./paths";
import { coverChoices, type Note, notes, processed, redCopies } from "./records";
import { reviews, statusOf } from "./reviews";
import type { Kind, State, Word } from "./state";
import { verdicts } from "./verdicts";

export type LibraryEntry = LibraryRow & {
  state: State;
  issues: string[];
  by: string | null;
  message: string | null;
  dates: string[];
  thumb: string | undefined;
  title: string;
  artist: string;
  year: number | null;
  audio: string;
  genre: string | null;
  label: string | null;
  original: string | null;
  edition: string | null;
  at: string | null;
  entries: number;
  word: Word | null;
  cover: string | null;
  slug: string | null;
};

function issuesFor(r: LibraryRow, keys: Map<string, Set<string>>, red: Record<string, string[]>, done: boolean): string[] {
  const out: string[] = [];
  if (r.sr.includes(",") || r.bits.includes(",")) out.push("mixed format");
  if (r.id3 > 0) out.push("ID3 in FLAC");
  if (r.pics === 0) out.push("no embedded art");
  for (const k of ["ALBUM", "ALBUMARTIST", "DATE"]) {
    if ((keys.get(k)?.size ?? 0) > 1) out.push(`${k.toLowerCase()} differs across tracks`);
  }
  if (!done && !(keys.has("MUSICBRAINZ_ALBUMID") || keys.has("MUSICBRAINZ ALBUM ID"))) out.push("no MusicBrainz ID");
  if (!red[r.path]) out.push("no RED copy");
  return out;
}

const mtime = (path: string): number => {
  try {
    return statSync(path).mtimeMs;
  } catch {
    return 0;
  }
};

export function thumbUrl(rel: string): string {
  return `/thumb/${rel}?v=${mtime(`${DATA}/${rel}`)}`;
}

function signature(): string {
  const files = [`${INVENTORY}/inventory.sqlite`, REVIEWS, VERDICTS, NOTES, `${INVENTORY}/music-red.json`];
  for (const name of readdirSync(CATALOGUE)) if (name.endsWith(".json")) files.push(`${CATALOGUE}/${name}`);
  return files.map(mtime).join(",");
}

const first = (v: unknown): string | null => {
  const x = Array.isArray(v) ? v[0] : v;
  return x === null || x === undefined || x === "" ? null : String(x);
};

const str = (v: unknown): string | null => {
  const x = Array.isArray(v) ? v.join(", ") : v;
  return x === null || x === undefined || x === "" ? null : String(x);
};

const yearOf = (v: string | null | undefined): number | null => {
  const m = /^(\d{4})/.exec(v ?? "");
  return m ? Number(m[1]) : null;
};

type Event = { at: string; by: string; kind: Kind; text: string };

let cache: { sig: string; rows: LibraryEntry[] } | null = null;

async function build(): Promise<LibraryEntry[]> {
  const [done, red, allReviews, allVerdicts, allNotes, choices] = await Promise.all([
    processed(),
    redCopies(),
    reviews(),
    verdicts(),
    notes(),
    coverChoices(),
  ]);
  const keys = albumKeyTags();
  const thumbs = thumbnails();
  const touched = new Map<string, number>();
  const rows = libraryRows().map((r): LibraryEntry => {
    const k = keys.get(r.id) ?? new Map<string, Set<string>>();
    const rec = done.get(r.path);
    const rs = allReviews.get(r.path) ?? [];
    const vs = allVerdicts.get(r.path) ?? [];
    const ns: Note[] = allNotes.get(r.path) ?? [];
    const decisions = [...rs, ...vs].map((x) => x.at).sort();
    const latest = decisions.at(-1);
    const resolved = rec ? new Date(rec.resolved).toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16) : null;
    const events: Event[] = [
      ...ns.map((n) => ({ at: n.at, by: n.by, kind: "note" as const, text: n.text })),
      ...vs.map((x) => ({ at: x.at, by: x.by, kind: x.verdict, text: x.message })),
      ...rs.map((x) => ({ at: x.at, by: x.by, kind: x.verdict, text: x.message })),
    ].sort((a, b) => a.at.localeCompare(b.at));
    const word = events.at(-1) ?? null;
    touched.set(r.path, latest ? Date.parse(latest) : rec ? Date.parse(rec.resolved) : 0);
    const dates = [...(k.get("DATE") ?? [])].sort();
    const choice = rec ? choices[rec.slug] : undefined;
    const blob = thumbs.get(r.id);
    const a = rec?.album;
    return {
      ...r,
      dates,
      issues: issuesFor(r, k, red, !!rec),
      ...(rec ? statusOf(rec, rs, vs) : { by: null, message: null, state: "triage" as const }),
      thumb: blob,
      title: str(a?.["title"]?.value) ?? r.album_dir,
      artist: str(a?.["album_artist"]?.value) ?? r.artist_dir,
      year: yearOf(str(a?.["original_date"]?.value)) ?? yearOf(dates[0]),
      audio: audio(r.bits, r.sr),
      genre: first(a?.["genre"]?.value),
      label: str(a?.["label"]?.value),
      original: str(a?.["original_date"]?.value),
      edition: str(a?.["date"]?.value),
      at: rec ? (latest ?? resolved) : null,
      entries: rs.length + vs.length + ns.length,
      word: word && { by: word.by, kind: word.kind, at: word.at, text: word.text },
      cover: choice ? thumbUrl(choice.master) : blob ? `/thumb/blob/${blob}` : null,
      slug: rec?.slug ?? null,
    };
  });
  return rows.sort((a, b) => touched.get(b.path)! - touched.get(a.path)!);
}

export async function library(): Promise<LibraryEntry[]> {
  const sig = signature();
  if (cache?.sig === sig) return cache.rows;
  const rows = await build();
  cache = { sig, rows };
  return rows;
}

export type Stats = {
  albums: number;
  artists: number;
  tracks: number;
  seconds: number;
  bytes: number;
  accepted: number;
  blocked: number;
  withAgents: number;
  triage: number;
  scanned: string | null;
};

export function libraryStats(rows: LibraryEntry[]): Stats {
  const count = (...s: State[]) => rows.filter((r) => s.includes(r.state)).length;
  return {
    albums: rows.length,
    artists: new Set(rows.map((r) => r.artist_dir)).size,
    tracks: rows.reduce((n, r) => n + r.n, 0),
    seconds: rows.reduce((n, r) => n + r.dur, 0),
    bytes: rows.reduce((n, r) => n + r.bytes, 0),
    accepted: count("accepted"),
    blocked: count("blocked"),
    withAgents: count("awaiting agents", "changes requested"),
    triage: count("triage"),
    scanned: scannedAt(),
  };
}
