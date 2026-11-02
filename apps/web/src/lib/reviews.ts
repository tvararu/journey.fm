import { appendFileSync } from "node:fs";

import { REVIEWS } from "./paths";
import type { AlbumRecord } from "./records";
import type { State } from "./state";

export type Verdict = "accept" | "request_changes";

export type Review = {
  at: string;
  album: string;
  by: string;
  verdict: Verdict;
  message: string;
  fingerprint: string;
  cover?: string;
};

export type ReviewStatus = Exclude<State, "triage">;
export type Status = { state: ReviewStatus; by: string | null; message: string | null };
type Flag = { at: string; by: string; verdict: string; message: string; fingerprint: string };

const UNREVIEWED = new Set(["acoustid"]);

export function fingerprint(rec: AlbumRecord): string {
  const value = (f: unknown) => (f && typeof f === "object" && "value" in f ? f.value : f);
  const values = {
    album: Object.fromEntries(
      Object.entries(rec.album)
        .filter(([k]) => !["ratings", "links"].includes(k))
        .map(([k, f]) => [k, value(f)]),
    ),
    edition: rec.edition_choice.release,
    tracks: rec.tracks.map((t) =>
      Object.fromEntries(Object.entries(t.fields).filter(([k]) => !UNREVIEWED.has(k)).map(([k, f]) => [k, f.value])),
    ),
  };
  return new Bun.CryptoHasher("sha256").update(JSON.stringify(values)).digest("hex").slice(0, 16);
}

export async function reviews(): Promise<Map<string, Review[]>> {
  const file = Bun.file(REVIEWS);
  const out = new Map<string, Review[]>();
  if (!(await file.exists())) return out;
  for (const line of (await file.text()).split("\n").filter(Boolean)) {
    const r = JSON.parse(line) as Review;
    out.set(r.album, [...(out.get(r.album) ?? []), r]);
  }
  return out;
}

export function statusOf(rec: AlbumRecord, list: Review[] | undefined, flags: Flag[] = []): Status {
  const events = [
    ...flags.filter((v) => v.verdict === "flag").map((v) => ({ at: v.at, by: v.by, fingerprint: v.fingerprint, kind: "flag", message: v.message })),
    ...(list ?? []).map((r) => ({ at: r.at, by: r.by, fingerprint: r.fingerprint, kind: r.verdict as string, message: r.message })),
  ].sort((x, y) => x.at.localeCompare(y.at));
  const last = events.at(-1);
  if (!last || last.fingerprint !== fingerprint(rec)) return { by: null, message: null, state: "awaiting agents" };
  const state = last.kind === "accept" ? "accepted" : last.kind === "flag" ? "blocked" : "changes requested";
  return { by: last.by, message: last.message, state };
}

export async function addReview(r: Review): Promise<void> {
  appendFileSync(REVIEWS, `${JSON.stringify(r)}\n`);
}
