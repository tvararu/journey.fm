import { empty, same } from "./format";
import type { Field, Value } from "./records";

export const FIELD_TAGS: Record<string, string[]> = {
  album_artist: ["ALBUMARTIST", "ALBUM_ARTIST"],
  barcode: ["BARCODE"],
  catalogue_number: ["CATALOGNUMBER"],
  country: ["RELEASECOUNTRY"],
  date: ["DATE"],
  genre: ["GENRE"],
  label: ["LABEL"],
  language: ["LANGUAGE"],
  media: ["MEDIA"],
  original_date: ["ORIGINALDATE"],
  release_type: ["RELEASETYPE"],
  title: ["ALBUM"],
};

export const FIELD_NAMES: Record<string, string> = {
  album_artist: "Album artist",
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
  release_type: "Release type",
  scene: "Scene",
  title: "Title",
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

export function alternatives(f: Field): [string, Value][] {
  return Object.entries(f.candidates).filter(([s, v]) => s !== "files" && !same(v, f.value));
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
