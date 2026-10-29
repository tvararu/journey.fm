import { readFileSync, writeFileSync } from "node:fs";

import { mb, red, REL_INC } from "./lib/fetch";
import { files, type InvFile } from "./lib/inventory";
import { INV, RAW } from "./lib/paths";
import { basename, dumps, fixed1, py, unescapeHtml } from "./lib/py";
import { save } from "./lib/raw";

type LabelInfo = { label?: { name?: string | null } | null; "catalog-number"?: string | null };
type Medium = { format?: string | null; tracks?: { length?: number | null }[] };
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
export type Torrent = {
  id: number;
  media: string;
  encoding: string;
  filePath?: string | null;
  remasterYear?: number | null;
  remasterTitle?: string | null;
  remasterRecordLabel?: string | null;
  remasterCatalogueNumber?: string | null;
};
type Group = { group: { id: number }; torrents: Torrent[] };

export function decodeLog(b64: string): string {
  const b = Buffer.from(b64, "base64");
  if (b[0] === 0xff && b[1] === 0xfe) return new TextDecoder("utf-16le").decode(b);
  if (b[0] === 0xfe && b[1] === 0xff) return new TextDecoder("utf-16be").decode(b);
  return new TextDecoder("utf-8", { ignoreBOM: true }).decode(b);
}

export function toc(log: string): number[] | null {
  const rows = [...log.matchAll(/^\s*(\d+)\s*\|\s*[\d:.]+\s*\|\s*[\d:.]+\s*\|\s*(\d+)\s*\|\s*(\d+)\s*$/gm)];
  const end = rows.at(-1);
  if (!end) return null;
  return [1, rows.length, Number(end[3]) + 1 + 150, ...rows.map((r) => Number(r[2]) + 150)];
}

const norm = (s: string | null | undefined): string => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "");

function key(f: InvFile): [number, number, string] {
  const lead = (s: string) => /^\d*/.exec(s)?.[0] ?? "";
  return [Number(lead(f.tags["DISCNUMBER"] ?? "1") || 1), Number(lead(f.tags["TRACKNUMBER"] ?? "0") || 0), f.relpath];
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
  if (tr.length !== fs.length) return `${tr.length} tracks vs ${fs.length} files`;
  const sorted = [...fs].sort(order);
  const off = tr.map((t, i) => Math.abs((t.length || 0) / 1000 - sorted[i]!.duration));
  return `${tr.length} tracks, worst length gap ${fixed1(Math.max(...off))} s`;
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

async function main(slug: string, path: string) {
  const fs = files(path);
  const redMap = JSON.parse(readFileSync(`${INV}/music-red.json`, "utf8")) as Record<string, string[]>;
  const redDirs = (redMap[path] ?? []).map(basename);
  const f0 = fs[0];
  if (!f0) throw new Error(`no files for ${path}`);
  const t0 = f0.tags;
  const artist = (t0["ALBUMARTIST"] || t0["ARTIST"]) ?? null;
  const album = t0["ALBUM"] ?? null;
  const report: Record<string, unknown> = { path, red_dirs: redDirs };

  let torrent: Torrent | null = null;
  let group: Group | null = null;
  if (redDirs.length) {
    const browse = await red<{ results?: { groupId: number }[] }>({ action: "browse", artistname: artist, groupname: album });
    const res = browse?.results ?? [];
    for (const g of res) {
      const full = (await red<Group>({ action: "torrentgroup", id: g.groupId }))!;
      const hit = full.torrents.find((t) => redDirs.includes(unescapeHtml(t.filePath || "")));
      if (hit) {
        group = save(slug, `red_group_${g.groupId}`, full);
        torrent = hit;
        break;
      }
    }
  }
  let discid: [string, string | null, string | null, string, string | null][] = [];
  if (torrent && group) {
    report["red"] = {
      group: group.group.id,
      torrent: torrent.id,
      media: torrent.media,
      year: torrent.remasterYear ?? null,
      title: torrent.remasterTitle ?? null,
      label: unescapeHtml(torrent.remasterRecordLabel || ""),
      catno: torrent.remasterCatalogueNumber ?? null,
      encoding: torrent.encoding,
    };
    const info = await red<{ torrent?: { ripLogIds?: number[] } }>({ action: "torrent", id: torrent.id });
    const detail = save(slug, `red_torrent_${torrent.id}`, info);
    for (const lid of detail?.torrent?.ripLogIds ?? []) {
      const riplog = await red<{ log?: string }>({ action: "riplog", id: torrent.id, logid: lid });
      const lg = save(slug, `red_riplog_${torrent.id}_${lid}`, riplog);
      const text = decodeLog(lg?.log ?? "");
      writeFileSync(`${RAW}/${slug}/red_riplog_${torrent.id}_${lid}.log`, text);
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
  const rgid = t0["MUSICBRAINZ_RELEASEGROUPID"] || t0["MUSICBRAINZ RELEASE GROUP ID"];
  if (torrent && torrent.media === "WEB" && rgid) {
    const year = torrent.remasterYear || 0;
    const q = { "release-group": rgid, inc: "labels+media", limit: 100 };
    const b = save(slug, `mb_rg_releases_${rgid}`, await mb<{ releases?: Release[] }>("release", q));
    for (const r of b?.releases ?? []) {
      const digital = (r.media ?? []).some((m) => m.format === "Digital Media");
      if (digital && Math.abs(Number((r.date || "0").slice(0, 4) || 0) - year) <= 1) {
        cands.push(["web, same year", r.id]);
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
  console.log(dumps(report));
}

if (import.meta.main) {
  const [slug, path] = Bun.argv.slice(2);
  if (!(slug && path)) {
    console.error("usage: music:edition <slug> <Music/Artist/Album>");
    process.exit(1);
  }
  if (process.env["REDACTED_API_KEY"] === undefined) throw new Error("REDACTED_API_KEY is not set");
  await main(slug, path);
}
