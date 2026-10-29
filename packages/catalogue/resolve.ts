import { Database } from "bun:sqlite";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

type J = any;
type Cands = Record<string, unknown>;
type Pick = (cands: Cands, order: string[]) => [unknown, string | null];
type Inv = Record<string, J> & { relpath: string; duration: number; tags: [string, string][]; pictures: J[] };

const HERE = `${import.meta.dir}/..`;
const META = process.env.JOURNEY_DATA ?? `${HERE}/data`;
const OUT = process.env.JOURNEY_OUT ?? `${META}/catalogue`;
const MONTHS = Object.fromEntries(
  "January February March April May June July August September October November December".split(" ").map((m, i) => [m, i + 1]),
);
const RED_TYPES: Record<number, string> = {
  1: "Album", 3: "Soundtrack", 5: "EP", 6: "Anthology", 7: "Compilation", 9: "Single", 11: "Live album", 13: "Remix",
  14: "Bootleg", 15: "Interview", 16: "Mixtape", 17: "Demo", 18: "Concert Recording", 19: "DJ Mix", 21: "Unknown",
};
const ASCII: Record<string, string> = {
  "‘": "'", "’": "'", "‚": "'", "‛": "'", "′": "'", "“": '"', "”": '"', "„": '"', "″": '"', "‐": "-", "‑": "-",
  "‒": "-", "–": "-", "—": "-", "―": "-", "−": "-", "…": "...", " ": " ", " ": " ", " ": " ",
};
const ASCII_RE = new RegExp(`[${Object.keys(ASCII).join("")}]`, "g");
const ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", rsquo: "’", lsquo: "‘", rdquo: "”", ldquo: "“",
  ndash: "–", mdash: "—", hellip: "…",
};

export const unescape = (s: string): string =>
  s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) =>
    e[0] === "#"
      ? String.fromCodePoint(e[1]?.toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10))
      : (ENTITIES[e] ?? m),
  );

const empty = (v: unknown) => v === null || v === undefined || v === "" || (Array.isArray(v) && v.length === 0);
const truthy = (v: unknown) => !empty(v) && v !== 0 && v !== false;
const and = <T>(a: unknown, b: () => T): T | null => (truthy(a) ? b() : null);

function plain(v: unknown): unknown {
  if (typeof v === "string") return v.replace(ASCII_RE, (c) => ASCII[c] ?? c).trim();
  if (Array.isArray(v)) return v.map(plain);
  return v;
}

function load(slug: string, name: string): J {
  const p = `${META}/raw/${slug}/${name}.json`;
  if (!existsSync(p)) return null;
  const d = JSON.parse(readFileSync(p, "utf8"));
  const keys = d && typeof d === "object" && !Array.isArray(d) ? Object.keys(d).sort().join() : "";
  return keys === "data,fetched" ? d.data : d;
}

function rymDate(s: string | null | undefined): string | null {
  if (!s) return null;
  const m = s.trim().match(/^(?:(\d{1,2}) )?(?:([A-Z][a-z]+) )?(\d{4})$/);
  if (!m) return null;
  const [, d, mo, y] = m;
  return [y, ...(mo ? [String(MONTHS[mo]).padStart(2, "0")] : []), ...(d ? [String(Number(d)).padStart(2, "0")] : [])].join("-");
}

function rymLinks(slug: string): J {
  const p = `${META}/raw/${slug}/rym-2026-10-29.html`;
  if (!existsSync(p)) return null;
  const h = readFileSync(p, "utf8");
  const row = (name: string) =>
    h.match(new RegExp(`<th class="info_hdr">\\s*${name}\\s*</th>\\s*<td[^>]*>(.*?)</td>`, "s"))?.[1] ?? "";
  const links = (frag: string, kind: string) =>
    [...frag.matchAll(new RegExp(`<a title="\\[${kind}(\\d+)\\]"[^>]*href="([^"]+)"[^>]*>([^<]+)</a>`, "g"))].map(
      ([, i, u, n]) => ({ name: unescape(n!), id: Number(i), url: `https://rateyourmusic.com${u}` }),
    );
  const g = row("Genres");
  const pri = g.match(/release_pri_genres">(.*?)<\/span>/s);
  const sec = g.match(/release_sec_genres">(.*?)<\/span>/s);
  return {
    artists: links(row("Artist"), "Artist"),
    primary: pri ? links(pri[1]!, "Genre") : [],
    secondary: sec ? links(sec[1]!, "Genre") : [],
    scenes: links(row("Scenes"), "Genre"),
  };
}

const datePick: Pick = (cands, order) => {
  const vals = order.filter((s) => truthy(cands[s])).map((s) => [s, cands[s] as string] as const);
  if (!vals.length) return [null, null];
  let [src, best] = vals[0]!;
  for (const [s, v] of vals.slice(1)) {
    if (v.length > best.length && v.startsWith(best)) [src, best] = [`${src}, refined by ${s}`, v];
  }
  return [best, src];
};

const first: Pick = (cands, order) => {
  for (const s of order) if (!empty(cands[s])) return [cands[s], s];
  return [null, null];
};

const catKey = (s: string) => s.toUpperCase().replace(/[^A-Z0-9]/g, "");

const union: Pick = (cands, order) => {
  const out: string[] = [];
  const from: string[] = [];
  for (const s of order) {
    for (const v of (cands[s] as string[] | null | undefined) ?? []) {
      if (out.some((x) => catKey(x) === catKey(v))) continue;
      out.push(v);
      if (!from.includes(s)) from.push(s);
    }
  }
  return out.length ? [out, from.join(" + ")] : [null, null];
};

function field(cands: Cands, order: string[], pick: Pick = first) {
  const [value, source] = pick(cands, order);
  return { value: plain(value), source, candidates: Object.fromEntries(Object.entries(cands).filter(([, v]) => !empty(v))) };
}

const splitLabels = (s: string | null | undefined) =>
  unescape(s ?? "").split(/ \/ |; /).map((x) => x.trim()).filter(Boolean);

function inventory(path: string): Inv[] {
  const db = new Database(`${META}/inventory/inventory.sqlite`, { readonly: true });
  const fs = db
    .query("select f.* from files f join albums a on a.id = f.album_id where a.path = ? order by f.relpath")
    .all(path) as Inv[];
  for (const f of fs) {
    f.tags = (db.query("select key, value from tags where file_id = ? order by idx").all(f["id"]) as J[]).map((r) => [r.key, r.value]);
    f.pictures = db.query("select * from pictures where file_id = ? order by idx").all(f["id"]);
  }
  db.close();
  return fs;
}

function tag(f: Inv, ...keys: string[]): string | null {
  for (const k of keys) for (const [kk, v] of f.tags) if (kk.toUpperCase() === k) return v;
  return null;
}

function tagall(fs: Inv[], ...keys: string[]): string[] {
  const seen: string[] = [];
  for (const f of fs) for (const [kk, v] of f.tags) if (keys.includes(kk.toUpperCase()) && !seen.includes(v)) seen.push(v);
  return seen;
}

function trackOrder(a: Inv, b: Inv): number {
  const n = (s: string | null) => Number(s?.match(/^\d*/)?.[0] || 0);
  const ka = [n(tag(a, "DISCNUMBER")) || 1, n(tag(a, "TRACKNUMBER"))];
  const kb = [n(tag(b, "DISCNUMBER")) || 1, n(tag(b, "TRACKNUMBER"))];
  return ka[0]! - kb[0]! || ka[1]! - kb[1]! || (a.relpath < b.relpath ? -1 : a.relpath > b.relpath ? 1 : 0);
}

const credit = (ac: J[] | null | undefined) => (ac ?? []).map((a) => a.name + (a.joinphrase ?? "")).join("");
const sortCredit = (ac: J[] | null | undefined) => (ac ?? []).map((a) => a.artist["sort-name"] + (a.joinphrase ?? "")).join("");
const artists = (ac: J[] | null | undefined) => (ac ?? []).map((a) => a.artist.name as string);

function siteLinks(ids: J, rymArtists: J[], rel: J, rg: J) {
  const out: [string, string][] = [
    ["MusicBrainz release", `https://musicbrainz.org/release/${ids.musicbrainz_release}`],
    ["MusicBrainz release group", `https://musicbrainz.org/release-group/${ids.musicbrainz_release_group}`],
  ];
  for (const a of ids.musicbrainz_album_artist) out.push(["MusicBrainz artist", `https://musicbrainz.org/artist/${a}`]);
  if (ids.rym) out.push(["RYM", ids.rym]);
  for (const a of rymArtists) out.push(["RYM artist", a.url]);
  if (ids.discogs_release) out.push(["Discogs release", `https://www.discogs.com/release/${ids.discogs_release}`]);
  if (ids.discogs_master) out.push(["Discogs master", `https://www.discogs.com/master/${ids.discogs_master}`]);
  if (ids.red_group) out.push(["RED", `https://redacted.sh/torrents.php?id=${ids.red_group}&torrentid=${ids.red_torrent}`]);
  if (ids.wikidata) out.push(["Wikidata", `https://www.wikidata.org/wiki/${ids.wikidata}`]);
  const covered = ["musicbrainz.org", "rateyourmusic.com", "discogs.com", "wikidata.org", "redacted.sh"];
  for (const r of [...(rel?.relations ?? []), ...(rg?.relations ?? [])]) {
    const u: string | undefined = r.url?.resource;
    if (!u) continue;
    const host = URL.parse(u)?.host.replace(/^www\./, "") ?? "";
    if (!covered.some((c) => host.endsWith(c)) && !out.some((x) => x[1] === u)) out.push([host, u]);
  }
  return out.map(([label, url]) => ({ label, url }));
}

function fetched(slug: string, name: string): string | null {
  const p = `${META}/raw/${slug}/${name}.json`;
  if (!existsSync(p)) return null;
  const d = JSON.parse(readFileSync(p, "utf8"));
  return d && typeof d === "object" && !Array.isArray(d) ? (d.fetched ?? "").slice(0, 10) || null : null;
}

function ratings(slug: string, choice: J, rym: J, rg: J, dr: J) {
  const out: J = {};
  const m = (rym?.rating ?? "").match(/([\d.]+) \/ 5\.0 from ([\d,]+) ratings/);
  if (m) out.RYM = { value: Number(m[1]), count: Number(m[2].replaceAll(",", "")), scale: 5, as_of: (rym.fetched ?? "").slice(0, 10) };
  let r = dr?.community?.rating ?? {};
  if (r.count) out.Discogs = { value: r.average, count: r.count, scale: 5, as_of: fetched(slug, `discogs_release_${choice.discogs_release}`) };
  r = rg?.rating ?? {};
  if (r["votes-count"]) out.MusicBrainz = { value: r.value, count: r["votes-count"], scale: 5, as_of: fetched(slug, `mb_rg_${choice.release_group}`) };
  return out;
}

export function timestamp(d = new Date()): string {
  const p = (n: number) => String(Math.abs(n)).padStart(2, "0");
  const off = -d.getTimezoneOffset();
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}` +
    `${off < 0 ? "-" : "+"}${p(Math.trunc(off / 60))}${p(off % 60)}`;
}

const round1 = (x: number) => Math.round(x * 10) / 10;

function resolve(slug: string, choice: J) {
  const { path, release: rid } = choice;
  const fs = inventory(path).sort(trackOrder);
  const rel = load(slug, `mb_release_${rid}`);
  const rg = load(slug, `mb_rg_${choice.release_group}`);
  const rym = load(slug, "rym-2026-10-29");
  const report = load(slug, "edition-report") ?? {};
  const rt = report.red ?? {};
  const has = Object.keys(rt).length > 0;
  const redg = has ? load(slug, `red_group_${rt.group}`).group : null;
  const dr = choice.discogs_release ? load(slug, `discogs_release_${choice.discogs_release}`) : null;
  const dm = choice.discogs_master ? load(slug, `discogs_master_${choice.discogs_master}`) : null;
  const caa = load(slug, `caa_release_${rid}`) ?? load(slug, `caa_rg_${choice.release_group}`);
  const f0 = fs[0]!;
  const lrclib = load(slug, "lrclib") ?? {};

  const li: J[] = rel["label-info"] ?? [];
  const rgTypes: unknown[] = rg ? [rg["primary-type"], ...(rg["secondary-types"] ?? [])] : [];
  const uniq = <T>(xs: T[]) => [...new Set(xs)];
  const album: J = {
    title: field({ MusicBrainz: rel.title, RYM: and(rym, () => rym.title), RED: and(redg, () => unescape(redg.name)), files: tag(f0, "ALBUM") },
      ["MusicBrainz", "RYM", "RED", "files"]),
    album_artist: field({
      MusicBrainz: credit(rel["artist-credit"]),
      RED: and(redg, () => redg.musicInfo.artists.map((a: J) => unescape(a.name)).join(", ")),
      RYM: and(rym, () => rym.artist), files: tag(f0, "ALBUMARTIST", "ALBUM_ARTIST", "ARTIST"),
    }, ["MusicBrainz", "RED", "RYM", "files"]),
    release_type: field({
      RYM: and(rym, () => rym.type), MusicBrainz: rgTypes.filter(truthy).join(" + ") || null,
      RED: and(redg, () => RED_TYPES[redg.releaseType] ?? null), files: tag(f0, "RELEASETYPE", "MUSICBRAINZ ALBUM TYPE"),
    }, ["RYM", "MusicBrainz", "RED", "files"]),
    original_date: field({
      MusicBrainz: and(rg, () => rg["first-release-date"]), RYM: and(rym, () => rymDate(rym.released)),
      RED: and(redg, () => String(redg.year)), files: tag(f0, "ORIGINALDATE", "ORIGINALYEAR"),
    }, ["MusicBrainz", "RYM", "files", "RED"], datePick),
    date: field({ MusicBrainz: rel.date, RED: and(rt.year, () => String(rt.year)), files: tag(f0, "DATE") },
      ["MusicBrainz", "RED", "files"], datePick),
    edition: field({ RED: rt.title, MusicBrainz: rel.disambiguation }, ["RED", "MusicBrainz"]),
    label: field({
      RED: splitLabels(rt.label), MusicBrainz: uniq(li.filter((l) => l.label).map((l) => l.label.name)),
      Discogs: and(dr, () => uniq((dr.labels ?? []).map((l: J) => l.name))), files: tagall(fs, "LABEL"),
    }, ["RED", "MusicBrainz", "Discogs", "files"]),
    catalogue_number: field({
      RED: rt.catno ? [rt.catno] : null,
      MusicBrainz: uniq(li.filter((l) => l["catalog-number"] && l["catalog-number"] !== "[none]").map((l) => l["catalog-number"])),
      Discogs: and(dr, () => uniq((dr.labels ?? []).filter((l: J) => l.catno !== "none").map((l: J) => l.catno))),
      files: tagall(fs, "CATALOGNUMBER"),
    }, ["RED", "MusicBrainz", "Discogs"], union),
    barcode: field({
      MusicBrainz: rel.barcode, Discogs: and(dr, () => (dr.identifiers ?? []).find((i: J) => i.type === "Barcode")?.value ?? null),
      files: tag(f0, "BARCODE"),
    }, ["MusicBrainz", "Discogs", "files"]),
    country: field({ MusicBrainz: rel.country, files: tag(f0, "RELEASECOUNTRY", "MUSICBRAINZ ALBUM RELEASE COUNTRY") }, ["MusicBrainz", "files"]),
    media: field({ MusicBrainz: rel.media.map((m: J) => m.format || "?").join(", "), RED: rt.media, files: tag(f0, "MEDIA") },
      ["MusicBrainz", "RED", "files"]),
    genre: field({
      RYM: and(rym, () => rym.primary),
      MusicBrainz: and(rg, () => [...(rg.genres ?? [])].sort((a: J, b: J) => b.count - a.count).map((g: J) => g.name)),
      Discogs: and(dm, () => dm.styles), RED: and(redg, () => (redg.tags ?? []).map((t: string) => t.replaceAll(".", " "))),
      files: tagall(fs, "GENRE"),
    }, ["RYM", "MusicBrainz", "Discogs", "files"]),
    genre_secondary: field({ RYM: and(rym, () => rym.secondary.filter((g: string) => !rym.primary.includes(g))) }, ["RYM"]),
    scene: field({ RYM: and(rym, () => rym.scenes) }, ["RYM"]),
    descriptors: field({ RYM: and(rym, () => rym.descriptors) }, ["RYM"]),
    language: field({ RYM: and(rym, () => rym.language), MusicBrainz: rel["text-representation"]?.language, files: tag(f0, "LANGUAGE") },
      ["RYM", "MusicBrainz", "files"]),
    recorded: field({ RYM: and(rym, () => rym.recorded) }, ["RYM"]),
    album_artist_sort: field({ MusicBrainz: sortCredit(rel["artist-credit"]), files: tag(f0, "ALBUMARTISTSORT", "SORT_ALBUM_ARTIST") }, ["MusicBrainz", "files"]),
    release_status: field({ MusicBrainz: rel.status?.toLowerCase() ?? null, files: tag(f0, "RELEASESTATUS", "MUSICBRAINZ ALBUM STATUS") }, ["MusicBrainz", "files"]),
    script: field({ MusicBrainz: rel["text-representation"]?.script ?? null, files: tag(f0, "SCRIPT") }, ["MusicBrainz", "files"]),
    asin: field({ MusicBrainz: rel.asin ?? null, files: tag(f0, "ASIN") }, ["MusicBrainz", "files"]),
    total_discs: field({ MusicBrainz: String(rel.media.length), files: tag(f0, "TOTALDISCS", "DISCTOTAL") }, ["MusicBrainz", "files"]),
  };
  album.ratings = ratings(slug, choice, rym, rg, dr);
  const front = (caa?.images ?? []).find((i: J) => i.front);
  const embedded = fs.flatMap((f) => f.pictures).find((p) => p.type === 3);
  const covers = existsSync(`${OUT}/covers.json`) ? JSON.parse(readFileSync(`${OUT}/covers.json`, "utf8")) : {};
  const chosen = covers[slug];
  const hash = chosen && new Bun.CryptoHasher("sha256").update(readFileSync(`${META}/${chosen.master}`)).digest("hex").slice(0, 12);
  album.cover = {
    value: chosen ? `${chosen.master}#${hash}` : (front?.image ?? null),
    source: chosen ? `${chosen.chosen.source}, picked by eye` : front ? "Cover Art Archive" : null,
    candidates: Object.fromEntries(Object.entries({
      "Cover Art Archive": front?.image,
      files: embedded && `embedded ${embedded.width}x${embedded.height} ${Math.floor(embedded.size / 1024)} KB`,
    }).filter(([, v]) => v)),
  };
  const links = rymLinks(slug);
  album.rym_links = links;
  const wd = (rg?.relations ?? []).find((r: J) => (r.url?.resource ?? "").includes("wikidata"));
  album.ids = {
    musicbrainz_release: rid, musicbrainz_release_group: choice.release_group,
    musicbrainz_album_artist: rel["artist-credit"].map((a: J) => a.artist.id),
    rym: and(rym, () => rym.url),
    rym_path: and(rym, () => rym.url.replace(/^https:\/\/rateyourmusic.com\/release\/|\/$/g, "")),
    rym_artist_id: links && links.artists.map((a: J) => a.id),
    rym_id: and(rym, () => (rym.catalog_id ?? "").match(/(\d+)$/)?.[1] ?? null),
    rym_genre_id: links && links.primary.map((g: J) => g.id),
    rym_secondary_genre_id: links && links.secondary.map((g: J) => g.id),
    rym_scene_id: links && links.scenes.map((g: J) => g.id),
    red_group: rt.group ?? null, red_torrent: rt.torrent ?? null,
    discogs_release: choice.discogs_release ?? null, discogs_master: choice.discogs_master ?? null,
    wikidata: wd ? wd.url.resource.split("/").at(-1) : null,
  };

  album.links = siteLinks(album.ids, album.rym_links?.artists ?? [], rel, rg);

  const mtracks: [unknown, J, number][] = rel.media.flatMap((m: J) => (m.tracks ?? []).map((t: J) => [m.position, t, m["track-count"]]));
  const tracks = fs.map((f, i) => {
    const [disc, t, count] = i < mtracks.length && mtracks.length === fs.length ? mtracks[i]! : [null, null, null];
    const rec = t?.recording ?? {};
    const ly = lrclib[f.relpath]?.result;
    return {
      file: f.relpath, duration: f.duration,
      fields: {
        disc: field({ MusicBrainz: and(disc, () => String(disc)), files: tag(f, "DISCNUMBER") }, ["MusicBrainz", "files"]),
        track: field({ MusicBrainz: t?.number ?? null, files: tag(f, "TRACKNUMBER") }, ["MusicBrainz", "files"]),
        title: field({ MusicBrainz: t?.title ?? null, files: tag(f, "TITLE") }, ["MusicBrainz", "files"]),
        artist: field({ MusicBrainz: t ? credit(t["artist-credit"]) : null, files: tag(f, "ARTIST") }, ["MusicBrainz", "files"]),
        length: field({ MusicBrainz: t?.length ? round1(t.length / 1000) : null, files: round1(f.duration) }, ["files", "MusicBrainz"]),
        artist_sort: field({ MusicBrainz: t ? sortCredit(t["artist-credit"]) : null, files: tag(f, "ARTISTSORT", "SORT_ARTIST") }, ["MusicBrainz", "files"]),
        artists: field({ MusicBrainz: t ? artists(t["artist-credit"]) : null, files: f.tags.filter(([k]) => k.toUpperCase() === "ARTISTS").map(([, v]) => v) }, ["MusicBrainz", "files"]),
        total_tracks: field({ MusicBrainz: count ? String(count) : null, files: tag(f, "TOTALTRACKS", "TRACKTOTAL") }, ["MusicBrainz", "files"]),
        isrc: field({ MusicBrainz: rec.isrcs?.length ? rec.isrcs : null, files: tag(f, "ISRC") }, ["MusicBrainz", "files"]),
        lyrics: field({
          "LRCLIB synced": ly?.syncedLyrics ?? null, "LRCLIB plain": ly?.plainLyrics ?? null, files: tag(f, "LYRICS", "UNSYNCEDLYRICS"),
        }, ["LRCLIB synced", "files", "LRCLIB plain"]),
        instrumental: field({ LRCLIB: ly?.instrumental || null }, ["LRCLIB"]),
      },
      ids: { musicbrainz_track: t?.id ?? null, musicbrainz_recording: rec.id ?? null, lrclib: ly?.id ?? null, musicbrainz_artist: t ? t["artist-credit"].map((a: J) => a.artist.id) : [] },
    };
  });
  return { slug, path, state: "processed", resolved: timestamp(), edition_choice: choice, album, tracks };
}

if (import.meta.main) {
  const choices: Record<string, J> = JSON.parse(readFileSync(`${OUT}/editions.json`, "utf8"));
  const rym: [string, string, string][] = [];
  for (const [slug, ch] of Object.entries(choices)) {
    const rec = resolve(slug, ch);
    const ids = rec.album.ids;
    if (ids.rym_id) rym.push([ch.path.split("/").slice(1).join("/"), ids.rym_id, ids.rym_path]);
    writeFileSync(`${OUT}/${slug}.json`, JSON.stringify(rec, null, 1));
    const keys = ["title", "original_date", "date", "label", "catalogue_number", "genre"];
    console.log(slug, Object.fromEntries(keys.map((k) => [k, rec.album[k].value])));
  }
  rym.sort((a, b) => (a.join("\t") < b.join("\t") ? -1 : 1));
  writeFileSync(process.env.JOURNEY_RYM_IDS ?? `${HERE}/rym-ids.tsv`, `folder\trym_id\trym_path\n${rym.map((r) => `${r.join("\t")}\n`).join("")}`);
}
