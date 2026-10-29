import { empty, same } from "./format";
import type { Value } from "./records";

export const FIELD_TAGS: Record<string, string[]> = {
  album_artist: ["ALBUMARTIST", "ALBUM_ARTIST"],
  album_artist_sort: ["ALBUMARTISTSORT"],
  asin: ["ASIN"],
  barcode: ["BARCODE"],
  catalogue_number: ["CATALOGNUMBER"],
  country: ["RELEASECOUNTRY"],
  date: ["DATE"],
  genre: ["GENRE"],
  label: ["LABEL"],
  language: ["LANGUAGE"],
  media: ["MEDIA"],
  original_date: ["ORIGINALDATE"],
  release_status: ["RELEASESTATUS"],
  release_type: ["RELEASETYPE"],
  script: ["SCRIPT"],
  title: ["ALBUM"],
  total_discs: ["TOTALDISCS", "DISCTOTAL"],
};

export const FIELD_NAMES: Record<string, string> = {
  album_artist: "Album artist",
  album_artist_sort: "Album artist sort",
  asin: "ASIN",
  barcode: "Barcode",
  catalogue_number: "Catalogue number",
  country: "Country",
  cover: "Cover",
  date: "Edition date",
  descriptors: "Descriptors",
  edition: "Edition",
  genre: "Genre",
  genre_secondary: "Secondary genres",
  label: "Label",
  language: "Language",
  media: "Media",
  original_date: "Original date",
  rating: "Rating",
  recorded: "Recorded",
  release_status: "Release status",
  release_type: "Release type",
  scene: "Scene",
  script: "Script",
  title: "Title",
  total_discs: "Total discs",
};

export const CHIP_FIELDS = new Set(["descriptors", "genre", "genre_secondary", "scene"]);
export const ALBUM_KEYS = new Set([
  "ALBUM",
  "ALBUMARTIST",
  "DATE",
  "ORIGINALDATE",
  "GENRE",
  "LABEL",
  "CATALOGNUMBER",
  "BARCODE",
  "MEDIA",
  "RELEASECOUNTRY",
  "RELEASETYPE",
  "MUSICBRAINZ_ALBUMID",
]);

export type Tag = { key: string; value: string };

export function valuesFor(tags: Map<number, Tag[]>, keys: string[]): string[] {
  const out: string[] = [];
  for (const list of tags.values()) {
    for (const t of list) {
      if (keys.includes(t.key.toUpperCase()) && !out.includes(t.value)) out.push(t.value);
    }
  }
  return out;
}

export function change(now: Value | undefined, proposed: Value): "" | "new" | "chg" {
  if (empty(proposed)) return "";
  if (empty(now)) return "new";
  return same(now, proposed) ? "" : "chg";
}

const PLAIN: [RegExp, string][] = [
  [/[’‘]/g, "'"],
  [/[“”]/g, '"'],
  [/[–—]/g, "-"],
  [/…/g, "..."],
];

export function invisible(a: Value | undefined, b: Value | undefined): string | null {
  if (typeof a !== "string" || typeof b !== "string" || a === b) return null;
  const plain = PLAIN.reduce((s, [re, to]) => s.replace(re, to), a);
  if (plain === b) {
    const ch = [...a].find((c, k) => c !== [...b][k]) ?? "";
    const to = PLAIN.reduce((s, [re, r]) => s.replace(new RegExp(re.source), r), ch);
    return `punctuation ${ch} → ${to} (plain ASCII)`;
  }
  if (a.toLowerCase() === b.toLowerCase()) return "case only";
  if (a.replace(/\s+/g, " ").trim() === b.replace(/\s+/g, " ").trim()) return "spacing only";
  return null;
}

export type KeySummary = { key: string; values: [string, number][]; count: number };

export function summarise(tags: Map<number, Tag[]>): KeySummary[] {
  const agg = new Map<string, Map<string, number>>();
  for (const list of tags.values()) {
    for (const t of list) {
      const m = agg.get(t.key) ?? new Map<string, number>();
      m.set(t.value, (m.get(t.value) ?? 0) + 1);
      agg.set(t.key, m);
    }
  }
  return [...agg.entries()]
    .map(([key, m]) => ({
      count: [...m.values()].reduce((a, b) => a + b, 0),
      key,
      values: [...m.entries()].sort((a, b) => b[1] - a[1]),
    }))
    .sort((a, b) => a.key.toUpperCase().localeCompare(b.key.toUpperCase()));
}
