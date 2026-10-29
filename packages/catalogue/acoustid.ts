import { existsSync, readFileSync } from "node:fs";

import { UA } from "./lib/fetch";
import { files } from "./lib/inventory";
import { META } from "./lib/paths";
import { save } from "./lib/raw";

type Print = { path: string; duration?: number; fingerprint?: string };
export type Match = { id: string; score: number; recordings: string[] };

const PRINTS = `${META}/fingerprints/music.jsonl`;
let last = 0;

export function prints(): Map<string, Print> {
  const out = new Map<string, Print>();
  if (!existsSync(PRINTS)) return out;
  for (const line of readFileSync(PRINTS, "utf8").split("\n").filter(Boolean)) {
    const p = JSON.parse(line) as Print;
    if (p.fingerprint) out.set(p.path, p);
  }
  return out;
}

async function lookup(p: Print): Promise<Match[]> {
  const key = process.env["ACOUSTID_API_KEY"];
  if (!key) throw new Error("ACOUSTID_API_KEY is not set");
  const body = new URLSearchParams({
    client: key, duration: String(Math.round(p.duration ?? 0)), fingerprint: p.fingerprint ?? "", meta: "recordingids",
  });
  for (let attempt = 0; attempt < 5; attempt++) {
    const wait = last + 350 - Date.now();
    if (wait > 0) await Bun.sleep(wait);
    last = Date.now();
    const r = await fetch("https://api.acoustid.org/v2/lookup", {
      body, headers: { "User-Agent": UA }, method: "POST", signal: AbortSignal.timeout(30_000),
    }).catch(() => null);
    const j = r?.ok ? ((await r.json()) as { status: string; results?: { id: string; score: number; recordings?: { id: string }[] }[] }) : null;
    if (j?.status === "ok") {
      return (j.results ?? []).map((m) => ({ id: m.id, recordings: (m.recordings ?? []).map((x) => x.id), score: m.score }));
    }
    await Bun.sleep(2000 * (attempt + 1));
  }
  throw new Error(`AcoustID lookup failed for ${p.path}`);
}

export async function album(slug: string, path: string, all = prints()): Promise<{ looked: number; missing: string[] }> {
  const out: Record<string, Match[] | null> = {};
  const missing: string[] = [];
  for (const f of files(path)) {
    const p = all.get(`${path}/${f.relpath}`);
    if (!p) {
      missing.push(f.relpath);
      out[f.relpath] = null;
      continue;
    }
    out[f.relpath] = await lookup(p);
  }
  save(slug, "acoustid", out);
  return { looked: Object.keys(out).length - missing.length, missing };
}

if (import.meta.main) {
  const [slug, path] = Bun.argv.slice(2);
  if (!(slug && path)) {
    console.error("usage: music:acoustid <slug> <Music/Artist/Album>");
    process.exit(1);
  }
  const r = await album(slug, path);
  console.log(slug, `${r.looked} looked up`, r.missing.length ? `no fingerprint for ${r.missing.length}: ${r.missing.join(", ")}` : "");
}
