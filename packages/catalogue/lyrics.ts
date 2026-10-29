import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";

import { META } from "./lib/paths";
import { timestamp } from "./resolve";

type Hit = { id: number; albumName?: string; duration?: number; instrumental?: boolean; syncedLyrics?: string | null; plainLyrics?: string | null };
type Found = { match: string | null; result: Hit | null; candidates: unknown[] };
type Rec = { album: { title: { value: string } }; tracks: { file: string; duration: number; fields: Record<string, { value: string }> }[] };

const UA = "journey.fm/0.1 ( private )";

async function get<T>(path: string, q: Record<string, string>): Promise<T | null> {
  const url = `https://lrclib.net/api/${path}?${new URLSearchParams(q)}`;
  let last = "";
  for (let attempt = 0; attempt < 8; attempt++) {
    const res = await fetch(url, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(30_000) }).catch(() => null);
    await Bun.sleep(500);
    if (res?.status === 404) return null;
    if (res?.ok) return (await res.json()) as T;
    last = res ? `HTTP ${res.status}` : "no response";
    await Bun.sleep(3000 * (attempt + 1));
  }
  throw new Error(`gave up on ${url} (${last})`);
}

const norm = (s: string | undefined) => (s ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const LIVE = /\blive\b|\d{4}-\d{2}-\d{2}|\bconcert\b|\bbootleg\b/i;

function rank(h: Hit, album: string, duration: number): number[] {
  const a = norm(h.albumName);
  const same = a && (a.includes(norm(album)) || norm(album).includes(a));
  return [Number(!h.syncedLyrics), Number(LIVE.test(h.albumName ?? "")), Number(!same), Math.abs((h.duration ?? 0) - duration)];
}

async function lookup(artist: string, title: string, album: string, duration: number): Promise<Found> {
  const hit = await get<Hit>("get-cached", { artist_name: artist, track_name: title, album_name: album, duration: String(Math.round(duration)) });
  if (hit) return { match: "exact", result: hit, candidates: [] };
  const all = (await get<Hit[]>("search", { artist_name: artist, track_name: title })) ?? [];
  const near = all.filter((h) => Math.abs((h.duration ?? 0) - duration) <= 2);
  const keyed = near.map((h) => [rank(h, album, duration), h] as const)
    .sort(([a], [b]) => a.reduce((d, x, i) => d || x - b[i]!, 0));
  const candidates = all.map((h) => ({ id: h.id, album: h.albumName ?? null, duration: h.duration ?? null, synced: !!h.syncedLyrics, instrumental: !!h.instrumental }));
  return { match: keyed[0] ? "search" : null, result: keyed[0]?.[1] ?? null, candidates };
}

const slugs = Bun.argv.slice(2);
const all = Object.keys(JSON.parse(readFileSync(`${META}/catalogue/editions.json`, "utf8")));
for (const slug of slugs.length ? slugs : all) {
  const rec: Rec = JSON.parse(readFileSync(`${META}/catalogue/${slug}.json`, "utf8"));
  const path = `${META}/raw/${slug}/lrclib.json`;
  const partial = `${path}.partial`;
  const out: Record<string, Found> = existsSync(partial) ? JSON.parse(readFileSync(partial, "utf8")) : {};
  mkdirSync(`${META}/raw/${slug}`, { recursive: true });
  let failed = 0;
  const rymFile = existsSync(`${META}/raw/${slug}`) ? readdirSync(`${META}/raw/${slug}`).filter((n) => /^rym-.*\.json$/.test(n)).sort().at(-1) : undefined;
  const rym = rymFile ? (JSON.parse(readFileSync(`${META}/raw/${slug}/${rymFile}`, "utf8")) as { data?: { descriptors?: string[] }; descriptors?: string[] }) : null;
  const instrumental = (rym?.data?.descriptors ?? rym?.descriptors ?? []).includes("instrumental");
  for (const t of rec.tracks) {
    const f = t.fields;
    if (!out[t.file]) {
      try {
        const found = await lookup(f["artist"]!.value, f["title"]!.value, rec.album.title.value, t.duration);
        out[t.file] = instrumental && !found.result ? { ...found, match: "RYM instrumental", result: { id: 0, instrumental: true } } : found;
        writeFileSync(partial, JSON.stringify(out));
      } catch (e) {
        failed++;
        console.log(slug, f["track"]!.value, f["title"]!.value, "-> failed, retried on the next run:", (e as Error).message);
        continue;
      }
    }
    const { match, result: hit } = out[t.file]!;
    const kind = hit && (hit.instrumental ? "instrumental" : hit.syncedLyrics ? "synced" : "plain");
    console.log(slug, f["track"]!.value, f["title"]!.value, "->", kind ?? "missing", match ?? "");
  }
  if (failed) {
    console.log(slug, `${failed} tracks failed; run lyrics ${slug} again to finish`);
    process.exitCode = 1;
    continue;
  }
  writeFileSync(path, JSON.stringify({ fetched: timestamp(), data: out }, null, 1));
  if (existsSync(partial)) unlinkSync(partial);
}
