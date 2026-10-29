import { VERDICTS } from "./paths";
import type { AlbumRecord } from "./records";
import { fingerprint } from "./reviews";

export type Verdict = {
  at: string;
  album: string;
  by: string;
  verdict: "approve" | "flag";
  message: string;
  fingerprint: string;
};

export type AgentState = { verdict: Verdict["verdict"]; message: string; stale: boolean };

export async function verdicts(): Promise<Map<string, Verdict[]>> {
  const file = Bun.file(VERDICTS);
  const out = new Map<string, Verdict[]>();
  if (!(await file.exists())) return out;
  for (const line of (await file.text()).split("\n").filter(Boolean)) {
    const v = JSON.parse(line) as Verdict;
    out.set(v.album, [...(out.get(v.album) ?? []), v]);
  }
  return out;
}

export function agentState(rec: AlbumRecord, list: Verdict[] | undefined): AgentState | null {
  const last = list?.at(-1);
  return last ? { message: last.message, stale: last.fingerprint !== fingerprint(rec), verdict: last.verdict } : null;
}

export async function addVerdict(v: Verdict): Promise<void> {
  const file = Bun.file(VERDICTS);
  const before = (await file.exists()) ? await file.text() : "";
  await Bun.write(VERDICTS, `${before}${JSON.stringify(v)}\n`);
}
