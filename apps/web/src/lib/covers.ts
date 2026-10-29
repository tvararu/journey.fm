import type { CoverCandidate } from "./records";
import { UPSCALERS } from "./upscale";

export const SHORT: Record<string, string> = {
  "Cover Art Archive (release)": "CAA release",
  "Cover Art Archive (release group)": "CAA release group",
  "Cover Art Archive (same catalogue number)": "CAA same cat. no.",
  "files (embedded)": "embedded in files",
  "files (folder)": "folder image",
};

const stem = (p: string) => (p.split("/").at(-1) ?? p).replace(/\.[^.]+$/, "");

export const upscaledBy = (c: CoverCandidate) => /^Upscaled \((.+)\)$/.exec(c.source)?.[1];

export const fronts = (candidates: CoverCandidate[]) => candidates.filter((c) => c.types.includes("Front"));

function parentOf(c: CoverCandidate, originals: CoverCandidate[]): CoverCandidate | undefined {
  const which = upscaledBy(c);
  const base = which ? stem(c.path).replace(`upscaled-${which}-`, "") : "";
  return originals.find((o) => stem(o.path) === base);
}

export type Group = { lead: CoverCandidate | undefined; kids: CoverCandidate[] };

export function groups(candidates: CoverCandidate[]): Group[] {
  const all = fronts(candidates);
  const originals = all.filter((c) => !upscaledBy(c));
  return [
    ...originals.map((o) => ({ kids: all.filter((c) => parentOf(c, originals) === o), lead: o as CoverCandidate | undefined })),
    ...all.filter((c) => upscaledBy(c) && !parentOf(c, originals)).map((c) => ({ kids: [c], lead: undefined })),
  ];
}

export function frontLabels(candidates: CoverCandidate[]): Map<string, string> {
  const all = fronts(candidates);
  const originals = all.filter((c) => !upscaledBy(c));
  const number = new Map(originals.map((o, i) => [o.id, i + 1]));
  const out = new Map<string, string>();
  for (const c of all) {
    const which = upscaledBy(c);
    if (!which) {
      out.set(c.id, `#${number.get(c.id)} ${SHORT[c.source] ?? c.source}`);
      continue;
    }
    const label = which in UPSCALERS ? UPSCALERS[which as keyof typeof UPSCALERS].label : which;
    const parent = parentOf(c, originals);
    out.set(c.id, parent ? `#${number.get(parent.id)} ↑ ${label}` : `↑ ${label}`);
  }
  return out;
}
