import { redTail } from "./format";
import { frontLabels } from "./covers";
import type { AlbumRecord, CoverCandidate, CoverChoice, Field } from "./records";

export type Check = { key: string; value: string; short: string | null; ok: boolean };

export function lyricsKind(fs: Record<string, Field>): string {
  if (fs["instrumental"]?.value) return "instrumental";
  const src = fs["lyrics"]?.source;
  return src === "LRCLIB synced" ? "synced" : src === "LRCLIB plain" ? "plain" : src === "files" ? "from files" : "missing";
}

const text = (f: Field | undefined) => {
  const v = f?.value;
  return Array.isArray(v) ? v.join(", ") : v === null || v === undefined ? "" : String(v);
};

export function checks(rec: AlbumRecord, choice: CoverChoice | undefined, candidates: CoverCandidate[], red: string[]): Check[] {
  const a = rec.album;
  const n = rec.tracks.length;
  const how = rec.edition_choice.how;
  const colon = how.indexOf(": ");
  const match = (colon >= 0 ? how.slice(colon + 2) : how).split(";")[0]!;
  const paired = rec.tracks.filter((t) => t.fields["title"]?.candidates["MusicBrainz"] != null).length;
  const gap = Math.max(
    0,
    ...rec.tracks.map((t) => {
      const mb = t.fields["length"]?.candidates["MusicBrainz"];
      return typeof mb === "number" ? Math.abs(mb - t.duration) : 0;
    }),
  );
  const g = gap.toFixed(1);
  const agrees = rec.tracks.filter((t) => t.ids["acoustid_agrees"] === true).length;
  const differs = rec.tracks.filter((t) => t.ids["acoustid_agrees"] === false).length;
  const kinds = new Map<string, number>();
  for (const t of rec.tracks) {
    const k = lyricsKind(t.fields);
    kinds.set(k, (kinds.get(k) ?? 0) + 1);
  }
  const labels = frontLabels(candidates);
  const label = choice ? labels.get(choice.chosen.id) ?? choice.chosen.source : "";
  const edition = [
    rec.edition_choice.release.slice(0, 8),
    [text(a["country"]), text(a["date"])].filter(Boolean).join(" "),
    text(a["catalogue_number"]),
    text(a["media"]),
  ]
    .filter(Boolean)
    .join(" · ");
  return [
    { key: "edition", value: edition, short: `edition ${rec.edition_choice.release.slice(0, 8)}`, ok: true },
    { key: "match", value: match, short: null, ok: true },
    {
      key: "tracks",
      value: `${paired}/${n} paired · worst length gap ${g} s`,
      short: `${paired}/${n} paired · lengths ${g} s`,
      ok: paired === n && gap <= 2,
    },
    {
      key: "acoustid",
      value: `${agrees}/${n} agree${differs > 0 ? `, ${differs} differ` : ""}`,
      short: `AcoustID ${agrees}/${n}`,
      ok: differs === 0,
    },
    {
      key: "cover",
      value: choice ? `${label} ${choice.chosen.width}×${choice.chosen.height}` : "no master",
      short: `cover ${choice ? label : "none"}`,
      ok: !!choice,
    },
    {
      key: "lyrics",
      value: `${[...kinds].map(([k, c]) => `${c} ${k}`).join(" · ")} · LRCLIB`,
      short: `lyrics ${kinds.get("synced") ?? 0} synced, ${kinds.get("plain") ?? 0} plain`,
      ok: true,
    },
    { key: "RED", value: red[0] ? redTail(red[0]) : "no RED copy", short: null, ok: red.length > 0 },
  ];
}

export function checkLine(cs: Check[]): string {
  return cs
    .filter((c) => c.short)
    .map((c) => `${c.ok ? "✓" : "!"} ${c.short}`)
    .join(" · ");
}
