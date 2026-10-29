import { VERDICTS } from "./paths";

export type Verdict = {
  at: string;
  album: string;
  by: string;
  verdict: "approve" | "flag";
  message: string;
  fingerprint: string;
};


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
  const file = Bun.file(VERDICTS);
  const before = (await file.exists()) ? await file.text() : "";
  await Bun.write(VERDICTS, `${before}${JSON.stringify(v)}\n`);
}
