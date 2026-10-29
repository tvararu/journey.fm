import { REVIEWS } from "./paths";
import type { AlbumRecord } from "./records";

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

export type ReviewStatus = "awaiting review" | "changes requested" | "updated since request" | "accepted" | "accepted, then changed";

export function fingerprint(rec: AlbumRecord): string {
  const value = (f: unknown) => (f && typeof f === "object" && "value" in f ? f.value : f);
  const values = {
    album: Object.fromEntries(
      Object.entries(rec.album)
        .filter(([k]) => !["ratings", "links"].includes(k))
        .map(([k, f]) => [k, value(f)]),
    ),
    edition: rec.edition_choice.release,
    tracks: rec.tracks.map((t) => Object.fromEntries(Object.entries(t.fields).map(([k, f]) => [k, f.value]))),
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

export function statusOf(rec: AlbumRecord, list: Review[] | undefined): ReviewStatus {
  const last = list?.at(-1);
  if (!last) return "awaiting review";
  const same = last.fingerprint === fingerprint(rec);
  if (last.verdict === "accept") return same ? "accepted" : "accepted, then changed";
  return same ? "changes requested" : "updated since request";
}

export async function addReview(r: Review): Promise<void> {
  const file = Bun.file(REVIEWS);
  const before = (await file.exists()) ? await file.text() : "";
  await Bun.write(REVIEWS, `${before}${JSON.stringify(r)}\n`);
}
