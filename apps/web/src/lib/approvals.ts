import { APPROVALS } from "./paths";
import type { AlbumRecord } from "./records";

export type Approval = { at: string; album: string; by: string; action: "approve" | "revoke"; fingerprint: string };

export type ApprovalState = { status: "approved" | "stale" | "none"; last: Approval | null };

export function fingerprint(rec: AlbumRecord): string {
  const values = {
    album: Object.fromEntries(Object.entries(rec.album).map(([k, f]) => [k, f && typeof f === "object" && "value" in f ? f.value : f])),
    edition: rec.edition_choice.release,
    tracks: rec.tracks.map((t) => Object.fromEntries(Object.entries(t.fields).map(([k, f]) => [k, f.value]))),
  };
  return new Bun.CryptoHasher("sha256").update(JSON.stringify(values)).digest("hex").slice(0, 16);
}

export async function approvals(): Promise<Map<string, Approval>> {
  const file = Bun.file(APPROVALS);
  const out = new Map<string, Approval>();
  if (!(await file.exists())) return out;
  for (const line of (await file.text()).split("\n").filter(Boolean)) {
    const a = JSON.parse(line) as Approval;
    out.set(a.album, a);
  }
  return out;
}

export function stateOf(rec: AlbumRecord | undefined, last: Approval | undefined): ApprovalState {
  if (!(rec && last) || last.action === "revoke") return { last: last ?? null, status: "none" };
  return { last, status: last.fingerprint === fingerprint(rec) ? "approved" : "stale" };
}

export async function record(a: Approval): Promise<void> {
  const file = Bun.file(APPROVALS);
  const before = (await file.exists()) ? await file.text() : "";
  await Bun.write(APPROVALS, `${before}${JSON.stringify(a)}\n`);
}
