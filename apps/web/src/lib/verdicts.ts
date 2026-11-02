import { appendFileSync } from "node:fs";

import { VERDICTS } from "./paths";
import type { AlbumRecord } from "./records";
import { fingerprint, statusOf, type Review } from "./reviews";

export type Question = {
  field: string;
  pick: { value: string; from: string };
  other: { value: string; from: string };
};

export type Verdict = {
  at: string;
  album: string;
  by: string;
  verdict: "approve" | "flag";
  message: string;
  fingerprint: string;
  question?: Question;
};

export function openQuestion(rec: AlbumRecord, rs: Review[], vs: Verdict[]): Question | null {
  if (statusOf(rec, rs, vs).state !== "blocked") return null;
  const fp = fingerprint(rec);
  const flag = vs.findLast((v) => v.verdict === "flag" && v.fingerprint === fp);
  return flag?.question ?? null;
}


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


export async function addVerdict(v: Verdict): Promise<void> {
  appendFileSync(VERDICTS, `${JSON.stringify(v)}\n`);
}
