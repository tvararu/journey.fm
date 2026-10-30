import { existsSync, readFileSync } from "node:fs";

import { RECORDS } from "./paths";

export const OVERRIDES = `${RECORDS}/overrides.jsonl`;
export type Override = { album: string; at: string; by: string; field: string; value: string | string[] | null; why: string };

export function overrides(path: string): Map<string, Override> {
  const out = new Map<string, Override>();
  if (!existsSync(OVERRIDES)) return out;
  for (const line of readFileSync(OVERRIDES, "utf8").split("\n")) {
    if (!line.trim()) continue;
    const o = JSON.parse(line) as Override;
    if (o.album !== path) continue;
    if (o.value === null) out.delete(o.field);
    else out.set(o.field, o);
  }
  return out;
}
