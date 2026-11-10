import { yearOf } from "./lib/albums";
import { mb, REL_INC } from "./lib/fetch";
import { discOf, files, type InvFile } from "./lib/inventory";
import { cachedRed, redCopy, type Torrent } from "./lib/red-cache";
import { dumps, fixed1, py, similarTitle, unescapeHtml } from "./lib/py";
import { save } from "./lib/raw";

type LabelInfo = { label?: { name?: string | null } | null; "catalog-number"?: string | null };
type Medium = { format?: string | null; tracks?: { length?: number | null; title?: string | null }[] };
export type Release = {
  id: string;
  date?: string | null;
  country?: string | null;
  barcode?: string | null;
  disambiguation?: string | null;
  media: Medium[];
  "label-info"?: LabelInfo[];
  "release-group": { id: string };
};

export function toc(log: string): number[] | null {
  const rows = [...log.matchAll(/^\s*(\d+)\s*\|\s*[\d:.]+\s*\|\s*[\d:.]+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$/gm)];
  const end = rows.at(-1);
  if (!end) return null;
  return [1, rows.length, Number(end[3]) + 1 + 150, ...rows.map((r) => Number(r[2]) + 150)];
}

const norm = (s: string | null | undefined): string => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");

function key(f: InvFile): [number, number, string] {
  const lead = (s: string) => /^\d*/.exec(s)?.[0] ?? "";
  return [discOf(f.relpath, f.tags["DISCNUMBER"]) || 1, Number(lead(f.tags["TRACKNUMBER"] ?? "0") || 0), f.relpath];
}

function order(a: InvFile, b: InvFile): number {
  const [x, y] = [key(a), key(b)];
  for (let i = 0; i < 3; i++) {
    if (x[i]! < y[i]!) return -1;
    if (x[i]! > y[i]!) return 1;
  }
  return 0;
}

export function matchLengths(rel: Release, fs: InvFile[]): string {
  const tr = (rel.media ?? []).flatMap((m) => m.tracks ?? []);
  const sorted = [...fs].sort(order);
  const gap = (t: (typeof tr)[number], f: InvFile) => Math.abs((t.length || 0) / 1000 - f.duration);
  if (tr.length === fs.length) {
    const off = tr.map((t, i) => gap(t, sorted[i]!));
    if (Math.max(...off) < 2) return `${tr.length} tracks, worst length gap ${fixed1(Math.max(...off))} s`;
  }
  const used = new Set<number>();
  const off: number[] = [];
  let missed = 0;
  for (const t of tr) {
    const j = sorted.findIndex((f, k) => !used.has(k) && similarTitle(t.title, f.tags["TITLE"]) && gap(t, f) <= 3);
    if (j < 0) {
      missed++;
      continue;
    }
    used.add(j);
    off.push(gap(t, sorted[j]!));
  }
  if (missed) return `${tr.length} tracks vs ${fs.length} files, only ${off.length} matched by title and length`;
  const extra = fs.length - tr.length;
  return `${tr.length} tracks${extra ? ` (+${extra} extra files)` : ""}, matched by title, worst length gap ${fixed1(Math.max(...off))} s`;
}

const GAPS = Array.from({ length: 20 }, (_, x) => `gap ${fixed1(x / 10)} s`);

export function evidence(rel: Release, fs: InvFile[], torrent: Torrent | null): string[] {
  const t0 = fs[0]!.tags;
  const cat = new Set((rel["label-info"] ?? []).map((l) => norm(l["catalog-number"])));
  cat.delete("");
  const ev: string[] = [];
  const lengths = matchLengths(rel, fs);
  if (GAPS.some((g) => lengths.endsWith(g))) ev.push("track lengths");
  if (torrent && cat.has(norm(torrent.remasterCatalogueNumber))) ev.push("RED catalogue number");
  if (cat.has(norm(t0["CATALOGNUMBER"]))) ev.push("file catalogue number");
  if (rel.barcode && rel.barcode === t0["BARCODE"]) ev.push("file barcode");
  if (torrent && (rel.date || "").slice(0, 4) === py(torrent.remasterYear)) ev.push("RED year");
  return ev;
}

const labels = (r: { "label-info"?: LabelInfo[] }): string =>
  (r["label-info"] ?? []).map((l) => `${py(l.label?.name)} ${py(l["catalog-number"])}`).join(", ");

export async function edition(slug: string, path: string): Promise<Record<string, unknown>> {
  const fs = files(path);
  const f0 = fs[0];
  if (!f0) throw new Error(`no files for ${path}`);
  const t0 = f0.tags;
  const artist = (t0["ALBUMARTIST"] || t0["ARTIST"]) ?? null;
  const album = t0["ALBUM"] ?? null;
  const match = cachedRed(slug);
  const report: Record<string, unknown> = { path, red_dirs: match?.dirs ?? [] };

  if (match) report["red_status"] = match.torrent ? "matched" : match.dirs.length ? "no match" : "not on RED";
  const copy = match && redCopy(slug, match);
  const torrent: Torrent | null = copy?.torrent ?? null;
  const group = copy?.group ?? null;
  let discid: [string, string | null, string | null, string, string | null][] = [];
  if (copy && torrent) {
    report["red"] = {
      group: copy.group.group.id,
      torrent: torrent.id,
      media: torrent.media,
      year: torrent.remasterYear ?? null,
      title: torrent.remasterTitle ?? null,
      label: unescapeHtml(torrent.remasterRecordLabel || ""),
      catno: torrent.remasterCatalogueNumber ?? null,
      encoding: torrent.encoding,
    };
    for (const text of copy.logs) {
      const t = toc(text);
      if (t) {
        report["toc"] = t;
        const q = { toc: t.join(" "), inc: "labels+release-groups", cdstubs: "no" };
        const d = save(slug, "mb_discid", await mb<{ releases?: Release[] }>("discid/-", q));
        discid = (d?.releases ?? []).map((r) => [r.id, r.date ?? null, r.country ?? null, labels(r), r.barcode ?? null]);
        report["discid_releases"] = discid;
        break;
      }
    }
  }

  const cands: [string, string][] = discid.map(([rid]) => ["discid", rid]);
  const tagged = t0["MUSICBRAINZ_ALBUMID"] || t0["MUSICBRAINZ ALBUM ID"];
  if (tagged) cands.push(["file tag", tagged]);
  let rgids = [t0["MUSICBRAINZ_RELEASEGROUPID"] || t0["MUSICBRAINZ RELEASE GROUP ID"]].filter((x): x is string => !!x);
  if (!rgids.length && !cands.length && artist && album) {
    const quote = (x: string) => `"${x.replace(/["\\]/g, " ")}"`;
    const titles = [...new Set([group && unescapeHtml(group.group.name), album].filter((x): x is string => !!x))];
    for (const title of titles) {
      const q = { query: `artist:${quote(artist)} AND releasegroup:${quote(title)}`, limit: 5 };
      type Hit = { id: string; score: number; "primary-type"?: string; "first-release-date"?: string };
      const found = save(slug, "mb_rg_search", await mb<{ "release-groups"?: Hit[] }>("release-group", q));
      const year = yearOf(t0);
      const album = (g: Hit) => Number(g["primary-type"] === "Album");
      const away = (g: Hit) => (year && g["first-release-date"] ? Math.abs(Number(g["first-release-date"].slice(0, 4)) - year) : 0);
      rgids = (found?.["release-groups"] ?? []).filter((g) => g.score >= 90).sort((x, y) => album(y) - album(x) || away(x) - away(y)).slice(0, 2).map((g) => g.id);
      if (rgids.length) break;
    }
    report["rg_search"] = rgids;
  }
  for (const rgid of rgids) {
    if (cands.some(([how]) => how !== "file tag") && !(torrent && torrent.media === "WEB")) break;
    const year = torrent?.remasterYear || 0;
    const q = { "release-group": rgid, inc: "labels+media", limit: 100 };
    const b = save(slug, `mb_rg_releases_${rgid}`, await mb<{ releases?: Release[] }>("release", q));
    for (const r of b?.releases ?? []) {
      const digital = (r.media ?? []).some((m) => m.format === "Digital Media");
      const near = Math.abs(Number((r.date || "0").slice(0, 4) || 0) - year) <= 1;
      if (torrent?.media === "WEB") {
        if (digital && near) cands.push(["web, same year", r.id]);
      } else {
        cands.push(["release group", r.id]);
      }
    }
  }
  const candidates: (Record<string, unknown> & { evidence: string[] })[] = [];
  report["candidates"] = candidates;
  const seen = new Set<string>();
  for (const [how, rid] of cands) {
    if (seen.has(rid)) continue;
    seen.add(rid);
    const rel = await mb<Release>(`release/${rid}`, { inc: REL_INC });
    if (!rel) continue;
    save(slug, `mb_release_${rid}`, rel);
    candidates.push({
      how,
      id: rid,
      date: rel.date ?? null,
      country: rel.country ?? null,
      format: rel.media.map((m) => m.format || "?").join(", "),
      labels: labels(rel),
      barcode: rel.barcode ?? null,
      title: rel.disambiguation ?? null,
      lengths: matchLengths(rel, fs),
      rg: rel["release-group"].id,
      evidence: evidence(rel, fs, torrent),
    });
  }
  candidates.sort((a, b) => b.evidence.length - a.evidence.length);
  save(slug, "edition-report", report);
  return report;
}

if (import.meta.main) {
  const [slug, path] = Bun.argv.slice(2);
  if (!(slug && path)) {
    console.error("usage: edition <slug> <Music/Artist/Album>");
    process.exit(1);
  }
  console.log(dumps(await edition(slug, path)));
}
