import { albumKeyTags, type LibraryRow, libraryRows, thumbnails } from "./inventory";
import { type Approval, approvals, stateOf } from "./approvals";
import { type AlbumRecord, processed, redCopies } from "./records";

export type LibraryEntry = LibraryRow & {
  state: "approved" | "processed" | "triage";
  issues: string[];
  dates: string[];
  thumb: string | undefined;
};

function issuesFor(r: LibraryRow, keys: Map<string, Set<string>>, red: Record<string, string[]>): string[] {
  const out: string[] = [];
  if (r.sr.includes(",") || r.bits.includes(",")) out.push("mixed format");
  if (r.id3 > 0) out.push("ID3 in FLAC");
  if (r.pics === 0) out.push("no embedded art");
  for (const k of ["ALBUM", "ALBUMARTIST", "DATE"]) {
    if ((keys.get(k)?.size ?? 0) > 1) out.push(`${k.toLowerCase()} differs across tracks`);
  }
  if (!(keys.has("MUSICBRAINZ_ALBUMID") || keys.has("MUSICBRAINZ ALBUM ID"))) out.push("no MusicBrainz ID");
  if (!red[r.path]) out.push("no RED copy");
  return out;
}

function stateFor(rec: AlbumRecord | undefined, last: Approval | undefined): LibraryEntry["state"] {
  if (!rec) return "triage";
  return stateOf(rec, last).status === "approved" ? "approved" : "processed";
}

export async function library(): Promise<LibraryEntry[]> {
  const [done, red, approved] = await Promise.all([processed(), redCopies(), approvals()]);
  const keys = albumKeyTags();
  const thumbs = thumbnails();
  return libraryRows().map((r) => {
    const k = keys.get(r.id) ?? new Map<string, Set<string>>();
    return {
      ...r,
      dates: [...(k.get("DATE") ?? [])].sort(),
      issues: issuesFor(r, k, red),
      state: stateFor(done.get(r.path), approved.get(r.path)),
      thumb: thumbs.get(r.id),
    };
  });
}
