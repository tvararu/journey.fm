import { appendFileSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";

import { CATALOGUE, META, RAW, RECORDS } from "./lib/paths";
import { load } from "./lib/raw";

// apps/web reads JOURNEY_ROOT when it loads, so it is imported after setting it.
process.env["JOURNEY_ROOT"] ??= `${import.meta.dir}/../..`;
const { fingerprint, reviews, statusOf } = await import("../../apps/web/src/lib/reviews");
const { verdicts } = await import("../../apps/web/src/lib/verdicts");
type J = any;
type Tags = [string, string][];

const MUSIC = "/mnt/pool/Music";
const STAGE = "/mnt/pool/music-meta/writes";
const ARCHIVE = "/mnt/pool/music-meta/archive";
const BACKUP = "/mnt/pool/music-meta/write-backup";
const CREDITS = ["composer", "lyricist", "writer", "arranger", "conductor", "performer", "producer", "engineer", "mixer", "remixer"];
const LANGUAGES: Record<string, string> = {
  Arabic: "ara", Chinese: "zho", Dutch: "nld", English: "eng", French: "fra", German: "deu", Greek: "ell",
  Haitian: "hat", Hungarian: "hun", Italian: "ita", Japanese: "jpn", Latin: "lat", Norwegian: "nor",
  Portuguese: "por", Romanian: "ron", Russian: "rus", Sanskrit: "san", Spanish: "spa", Swedish: "swe", Ukrainian: "ukr",
};

const value = (f: J) => (f && typeof f === "object" && !Array.isArray(f) && "value" in f ? f.value : f);
const list = (v: unknown): string[] =>
  (Array.isArray(v) ? v : [v]).filter((x) => x !== null && x !== undefined && x !== "").map(String);
const named = (xs: { name: string; id: number }[] | undefined) => (xs ?? []).map((x) => `${x.name} (${x.id})`);

function languages(f: J): string[] {
  const v = value(f);
  if (!v) return [];
  if (f.source !== "RYM") return [String(v)];
  return String(v).split(", ").map((n) => {
    const code = LANGUAGES[n];
    if (!code) throw new Error(`no ISO 639-3 code for language ${n}`);
    return code;
  });
}

function rym(slug: string): J {
  const dir = `${RAW}/${slug}`;
  const name = readdirSync(dir).filter((n) => /^rym-\d{4}-\d{2}-\d{2}\.json$/.test(n)).sort().at(-1);
  return name ? JSON.parse(readFileSync(`${dir}/${name}`, "utf8")) : null;
}

function albumTags(rec: J, stamp: string): Tags {
  const a = rec.album;
  const ids = a.ids;
  const rg = load(rec.slug, `mb_rg_${rec.edition_choice.release_group}`) as J;
  const page = rym(rec.slug);
  const links = a.rym_links ?? {};
  const rating = a.ratings?.RYM;
  const out: Tags = [];
  const put = (k: string, v: unknown) => {
    for (const x of list(v)) out.push([k, x]);
  };
  put("ALBUM", value(a.title));
  put("ALBUMARTIST", value(a.album_artist));
  put("ALBUMARTISTSORT", value(a.album_artist_sort));
  put("RELEASETYPE", rg ? [rg["primary-type"], ...(rg["secondary-types"] ?? [])].filter(Boolean).map((t: string) => t.toLowerCase()) : []);
  put("RELEASESTATUS", value(a.release_status));
  put("ORIGINALDATE", value(a.original_date));
  put("DATE", value(a.date));
  put("LABEL", value(a.label));
  put("CATALOGNUMBER", value(a.catalogue_number));
  put("BARCODE", value(a.barcode));
  put("RELEASECOUNTRY", value(a.country));
  put("MEDIA", value(a.media));
  put("SCRIPT", value(a.script));
  put("LANGUAGE", languages(a.language));
  put("GENRE", value(a.genre));
  put("TOTALDISCS", value(a.total_discs));
  put("MUSICBRAINZ_ALBUMID", ids.musicbrainz_release);
  put("MUSICBRAINZ_RELEASEGROUPID", ids.musicbrainz_release_group);
  put("MUSICBRAINZ_ALBUMARTISTID", ids.musicbrainz_album_artist);
  put("RYM_ID", ids.rym_id);
  put("RYM_URL", ids.rym);
  put("RYM_ARTIST", named(links.artists));
  put("RYM_TYPE", value(a.release_type) && a.release_type.source === "RYM" ? String(value(a.release_type)).split(", ") : page?.type);
  put("RYM_GENRE", named(links.primary));
  put("RYM_SECONDARY_GENRE", named(links.secondary));
  put("RYM_SCENE", named(links.scenes));
  put("RYM_DESCRIPTORS", list(value(a.descriptors)).join(", "));
  if (rating) {
    put("RYM_RATING_SCORE", rating.value);
    put("RYM_RATING_VOTES", rating.count);
  }
  put("RYM_RANK", page?.ranked);
  put("RYM_FETCHED_AT", (page?.fetched ?? "").slice(0, 10));
  put("CATALOGUED_AT", stamp);
  put("CATALOGUE_FINGERPRINT", fingerprint(rec));
  return out;
}

function trackTags(rec: J, t: J): Tags {
  const f = t.fields;
  const out: Tags = [];
  const put = (k: string, v: unknown) => {
    for (const x of list(v)) out.push([k, x]);
  };
  const disc = value(f.disc);
  put("DISCNUMBER", disc);
  put("TRACKNUMBER", value(f.track));
  put("TOTALTRACKS", value(f.total_tracks) ?? rec.tracks.filter((x: J) => value(x.fields.disc) === disc).length);
  put("TITLE", value(f.title));
  put("ARTIST", value(f.artist));
  put("ARTISTSORT", value(f.artist_sort));
  put("ARTISTS", value(f.artists));
  put("ISRC", value(f.isrc));
  for (const c of CREDITS) put(c.toUpperCase(), value(f[c]));
  put("MUSICBRAINZ_TRACKID", t.ids?.musicbrainz_recording);
  put("MUSICBRAINZ_RELEASETRACKID", t.ids?.musicbrainz_track);
  put("MUSICBRAINZ_ARTISTID", t.ids?.musicbrainz_artist);
  put("ACOUSTID_ID", value(f.acoustid));
  put("LRCLIB_ID", t.ids?.lrclib);
  return out;
}

const q = (s: string) => `'${s.replaceAll("'", "'\\''")}'`;

function stage(rec: J, stamp: string, dir: string, backup: boolean): void {
  const covers = JSON.parse(readFileSync(`${CATALOGUE}/covers.json`, "utf8"))[rec.slug];
  if (!covers) throw new Error(`no cover master for ${rec.slug}`);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  writeFileSync(`${dir}/cover.jpg`, readFileSync(`${META}/${covers.master}`));
  writeFileSync(`${dir}/embed.jpg`, readFileSync(`${META}/${covers.embed}`));
  const album = albumTags(rec, stamp);
  const rel = rec.path.replace(/^Music\//, "");
  const A = `${MUSIC}/${rel}`;
  const S = `${STAGE}/${rec.slug}`;
  const sh = ["set -euo pipefail", `A=${q(A)}`, `S=${q(S)}`];
  if (backup) sh.push(`B=${q(`${BACKUP}/${rel}`)}`, `if [[ ! -e "$B" ]]; then mkdir -p "$B" && cp -a "$A/." "$B/"; fi`);
  rec.tracks.forEach((t: J, i: number) => {
    const n = String(i + 1).padStart(3, "0");
    const tags = [...album, ...trackTags(rec, t)];
    for (const [k, v] of tags) if (/[\r\n]/.test(v)) throw new Error(`${rec.slug} ${t.file} ${k} has a line break`);
    writeFileSync(`${dir}/${n}.tags`, tags.map(([k, v]) => `${k}=${v}\n`).join(""));
    const lyrics = value(t.fields.lyrics);
    const F = `"$A"/${q(t.file)}`;
    let set = `metaflac --remove-all-tags --import-tags-from="$S/${n}.tags"`;
    if (lyrics) {
      writeFileSync(`${dir}/${n}.lyrics`, String(lyrics));
      set += ` --set-tag-from-file="LYRICS=$S/${n}.lyrics"`;
    }
    sh.push(`metaflac --remove --block-type=PICTURE ${F}`, `${set} --import-picture-from="3||||$S/embed.jpg" ${F}`);
  });
  const files = rec.tracks.map((t: J) => `"$A"/${q(t.file)}`).join(" ");
  sh.push(
    `files=(${files})`,
    `if (($(for f in "\${files[@]}"; do metaflac --no-filename --show-sample-rate --show-bps --show-channels "$f" | paste -sd' '; done | sort -u | wc -l) > 1)); then`,
    `  for f in "\${files[@]}"; do metaflac --add-replay-gain "$f"; metaflac --remove-tag=REPLAYGAIN_ALBUM_GAIN --remove-tag=REPLAYGAIN_ALBUM_PEAK "$f"; done`,
    `else metaflac --add-replay-gain "\${files[@]}"; fi`,
    `flac -t -s "\${files[@]}"`,
    `shopt -s nullglob nocaseglob`,
    `old=("$A"/*.jpg "$A"/*.jpeg "$A"/*.png)`,
    `if ((\${#old[@]})); then mkdir -p ${q(`${ARCHIVE}/${rel}`)}; mv "\${old[@]}" ${q(`${ARCHIVE}/${rel}`)}/; fi`,
    `install -m 644 "$S/cover.jpg" "$A/cover.jpg"`,
    `echo WROTE ${rec.slug}`,
  );
  writeFileSync(`${dir}/write.sh`, `${sh.join("\n")}\n`);
}

function run(cmd: string[]): void {
  const p = Bun.spawnSync(cmd, { stdout: "inherit", stderr: "inherit" });
  if (p.exitCode !== 0) throw new Error(`${cmd[0]} failed (${p.exitCode})`);
}

function expected(rec: J, album: Tags, t: J): string[] {
  const lyrics = value(t.fields.lyrics);
  return [...album, ...trackTags(rec, t), ...(lyrics ? [["LYRICS", String(lyrics)] as [string, string]] : [])].map(([k, v]) => `${k}=${v}`);
}

function diff(want: string[], got: string[]): string[] {
  const left = new Map<string, number>();
  for (const x of got) left.set(x, (left.get(x) ?? 0) + 1);
  const missing = want.filter((x) => {
    const n = left.get(x) ?? 0;
    if (n) left.set(x, n - 1);
    return !n;
  });
  const extra = [...left].flatMap(([x, n]) => Array(n).fill(x));
  const short = (x: string) => (x.length > 80 ? `${x.slice(0, 80)}…` : x);
  return [...missing.map((x) => `missing ${short(x)}`), ...extra.map((x) => `extra ${short(x)}`)];
}

function verify(rec: J): string[] {
  const A = `${MUSIC}/${rec.path.replace(/^Music\//, "")}`;
  const sh = ["set -uo pipefail", `A=${q(A)}`];
  rec.tracks.forEach((t: J, i: number) => {
    const F = `"$A"/${q(t.file)}`;
    sh.push(`echo @@FILE ${i}`, `metaflac --list --block-type=VORBIS_COMMENT ${F}`, `echo @@PICTURE`, `metaflac --list --block-type=PICTURE ${F} | grep -E '^  (type|MIME type|width|height): '`);
  });
  sh.push(`echo @@COVER`, `stat -c '%a %s' "$A/cover.jpg"`, `echo @@IMAGES`, `cd "$A" && shopt -s nullglob nocaseglob && printf '%s\\n' *.jpg *.jpeg *.png`);
  const p = Bun.spawnSync(["ssh", "sol", "bash", "-s"], { stdin: Buffer.from(sh.join("\n")) });
  const out = p.stdout.toString();
  const sections = out.split(/^@@/m).slice(1);
  const problems: string[] = [];
  const album = albumTags(rec, stamp).filter(([k]) => k !== "CATALOGUED_AT");
  const gains = new Set<string>();
  for (const [n, s] of sections.entries()) {
    if (!s.startsWith("FILE ")) continue;
    const i = Number(s.slice(5, s.indexOf("\n")));
    const t = rec.tracks[i];
    const pic = sections[n + 1]?.startsWith("PICTURE\n") ? sections[n + 1]!.slice(8) : "";
    const lines = s.split("\n");
    const start = lines.findIndex((l) => /^  comments: \d+$/.test(l));
    const tags: string[] = [];
    for (const l of lines.slice(start + 1)) {
      const m = /^    comment\[\d+\]: ([\s\S]*)$/.exec(l);
      if (m) tags.push(m[1]!);
      else if (tags.length) tags[tags.length - 1] += `\n${l}`;
    }
    if (tags.length) tags[tags.length - 1] = tags[tags.length - 1]!.replace(/\n$/, "");
    const rg = tags.filter((x) => x.startsWith("REPLAYGAIN_"));
    const at = tags.filter((x) => x.startsWith("CATALOGUED_AT="));
    for (const k of ["REFERENCE_LOUDNESS", "TRACK_GAIN", "TRACK_PEAK"]) if (!rg.some((x) => x.startsWith(`REPLAYGAIN_${k}=`))) problems.push(`${t.file}: no REPLAYGAIN_${k}`);
    gains.add(rg.filter((x) => x.startsWith("REPLAYGAIN_ALBUM_")).sort().join(" "));
    if (at.length !== 1 || !/^CATALOGUED_AT=\d{4}-\d{2}-\d{2}$/.test(at[0]!)) problems.push(`${t.file}: bad CATALOGUED_AT`);
    const rest = tags.filter((x) => !x.startsWith("REPLAYGAIN_") && !x.startsWith("CATALOGUED_AT="));
    for (const d of diff(expected(rec, album, t), rest)) problems.push(`${t.file}: ${d}`);
    const pl = pic.split("\n").filter(Boolean);
    if (pl.filter((l) => l === "  type: 6 (PICTURE)").length !== 1 || !pl.includes("  type: 3 (Cover (front))") || !pl.includes("  MIME type: image/jpeg")) problems.push(`${t.file}: picture is not one JPEG front cover (${pl.join("; ")})`);
  }
  if (sections.filter((x) => x.startsWith("FILE ")).length !== rec.tracks.length) problems.push(`read ${sections.length} sections for ${rec.tracks.length} tracks: ${p.stderr.toString().trim()}`);
  if (gains.size !== 1) problems.push(`album gain differs between tracks`);
  const covers = JSON.parse(readFileSync(`${CATALOGUE}/covers.json`, "utf8"))[rec.slug];
  const cover = sections.find((x) => x.startsWith("COVER\n"))?.slice(6).trim();
  if (cover !== `644 ${statSync(`${META}/${covers.master}`).size}`) problems.push(`cover.jpg is "${cover}"`);
  const images = sections.find((x) => x.startsWith("IMAGES\n"))?.slice(7).trim();
  if (images !== "cover.jpg") problems.push(`root images: ${images?.replaceAll("\n", ", ")}`);
  return problems;
}

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { plan: { type: "boolean" }, backup: { type: "boolean" }, verify: { type: "boolean" } },
});
if (!positionals.length) {
  console.error("usage: write <slug>... [--plan] [--backup] [--verify]");
  process.exit(1);
}
const rv = await reviews();
const vs = await verdicts();
const stamp = new Date().toISOString().slice(0, 10);
for (const slug of positionals) {
  const rec = JSON.parse(readFileSync(`${CATALOGUE}/${slug}.json`, "utf8"));
  const state = statusOf(rec, rv.get(rec.path), vs.get(rec.path)).state;
  if (state !== "accepted") throw new Error(`${slug} is ${state}, not accepted`);
  if (values.verify) {
    const problems = verify(rec);
    console.log(problems.length ? `BAD ${slug}\n${problems.map((x) => `  ${x}`).join("\n")}` : `OK ${slug}`);
    if (problems.length) process.exitCode = 1;
    continue;
  }
  if (values.plan) {
    const album = albumTags(rec, stamp);
    for (const t of rec.tracks) {
      console.log(`# ${t.file}`);
      for (const [k, v] of [...album, ...trackTags(rec, t)]) console.log(`${k}=${v}`);
      const lyrics = value(t.fields.lyrics);
      if (lyrics) console.log(`LYRICS=${String(lyrics).split("\n")[0]} … (${String(lyrics).split("\n").length} lines)`);
      console.log();
    }
    continue;
  }
  const dir = `${META}/writes/${slug}`;
  stage(rec, stamp, dir, !!values.backup);
  run(["ssh", "sol", "mkdir", "-p", `${STAGE}/${slug}`]);
  run(["rsync", "-a", "--delete", `${dir}/`, `sol:${STAGE}/${slug}/`]);
  run(["ssh", "sol", "bash", `${STAGE}/${slug}/write.sh`]);
  appendFileSync(`${RECORDS}/writes.jsonl`, `${JSON.stringify({ album: rec.path, slug, at: new Date().toISOString().slice(0, 16), by: "claude", fingerprint: fingerprint(rec) })}\n`);
}
