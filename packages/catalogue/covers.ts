import { closeSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { relative } from "node:path";

import { fetchJson, UA } from "./lib/fetch";
import { inventory } from "./lib/inventory";
import { CATALOGUE, INV, META, RAW } from "./lib/paths";
import { basename, dump, py, squash, stamp, truthy } from "./lib/py";
import { load, save } from "./lib/raw";

const EMBED_PX = 1200;
const AUTO_UPSCALE_BELOW = 2000;
const EMBED_QUALITY = 88;
const MASTER_QUALITY = 95;
const MOZJPEG = process.env.MOZJPEG ?? ["/opt/homebrew/opt/mozjpeg/bin/cjpeg", "/usr/bin/mozjpeg-cjpeg"].find(existsSync) ?? "cjpeg";

type Image = { image: string; types: string[]; comment?: string | null; front?: boolean };
type Caa = { images?: Image[] };
type Choice = { path: string; release: string; release_group: string };
type Candidate = {
  id: string;
  source: string;
  url: string | null;
  path: string;
  types: string[];
  note: string | null;
  width: number;
  height: number;
  bytes: number;
  sha256: string;
};

const readJson = <T>(p: string): T => JSON.parse(readFileSync(p, "utf8")) as T;
const size = (p: string): number => statSync(p).size;
const sha256 = (p: string): string => new Bun.CryptoHasher("sha256").update(readFileSync(p)).digest("hex");
const tail = (url: string): string => url.slice(url.lastIndexOf("/") + 1);

function run(cmd: string[]): void {
  const p = Bun.spawnSync(cmd, { stdio: ["inherit", "inherit", "inherit"] });
  if (p.exitCode !== 0) throw new Error(`${cmd[0]} exited with ${p.exitCode}`);
}

const capture = (cmd: string[]): Buffer => Bun.spawnSync(cmd, { stdout: "pipe", stderr: "pipe" }).stdout;

function dims(path: string): [number, number] {
  const out = capture(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", path]).toString();
  const m = out.trim().split(",").map(Number);
  if (m.length !== 2 || m.some((x) => !x)) throw new Error(`ffprobe could not size ${path}`);
  return [m[0]!, m[1]!];
}

async function get(url: string, dest: string): Promise<string> {
  if (!existsSync(dest)) {
    for (let attempt = 0; ; attempt++) {
      await Bun.sleep(500 + 3000 * attempt);
      const r = await fetch(url, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(300_000) })
        .then(async (res) => (res.ok ? new Uint8Array(await res.arrayBuffer()) : res))
        .catch((e: Error) => e);
      if (r instanceof Uint8Array) {
        writeFileSync(dest, r);
        break;
      }
      const why = r instanceof Response ? `HTTP ${r.status} ${r.statusText}` : r.message;
      if (attempt >= 3 || (r instanceof Response && r.status < 500 && r.status !== 429)) throw new Error(`${why} for ${url}`);
    }
  }
  return dest;
}

function blob(h: string): string {
  const x = readdirSync(`${INV}/blobs`).find((n) => n.startsWith(h));
  if (x === undefined) throw new Error(`no blob for ${h}`);
  return `${INV}/blobs/${x}`;
}

function candidate(source: string, path: string, url: string | null, types: string[], note: string | null): Candidate {
  const [w, h] = dims(path);
  return {
    id: `${source}:${basename(path)}`,
    source,
    url,
    path: relative(META, path),
    types: [...types],
    note,
    width: w,
    height: h,
    bytes: size(path),
    sha256: sha256(path),
  };
}

type Credit = { name: string; joinphrase?: string };

async function stores(slug: string, choice: Choice): Promise<void> {
  const rel = load(slug, `mb_release_${choice.release}`) as { title: string; "artist-credit": Credit[] } | null;
  if (!rel) return;
  const artist = rel["artist-credit"].map((a) => a.name + (a.joinphrase ?? "")).join("");
  const first = rel["artist-credit"][0]?.name ?? artist;
  const same = (a: string | undefined, b: string) => {
    const x = squash(a);
    const y = squash(b);
    return !!x && (x === y || x.startsWith(y) || y.startsWith(x));
  };
  const q = new URLSearchParams({ entity: "album", limit: "10", term: `${first} ${rel.title}` });
  const it = await fetchJson<{ results?: { artistName?: string; collectionName?: string }[] }>(`https://itunes.apple.com/search?${q}`, 3.1);
  const hit = (it?.results ?? []).find((r) => same(r.artistName, first) && same(r.collectionName, rel.title)) ?? null;
  save(slug, "itunes", hit);
  const dq = new URLSearchParams({ q: `artist:"${first}" album:"${rel.title}"` });
  const dz = await fetchJson<{ data?: { id: number; title?: string; artist?: { name?: string } }[] }>(`https://api.deezer.com/search/album?${dq}`, 0.3);
  const dhit = (dz?.data ?? []).find((r) => same(r.artist?.name, first) && same(r.title, rel.title));
  save(slug, "deezer", dhit ? await fetchJson(`https://api.deezer.com/album/${dhit.id}`, 0.3) : null);
}

async function candidates(slug: string, choice: Choice): Promise<Candidate[]> {
  const d = `${RAW}/${slug}/covers`;
  mkdirSync(d, { recursive: true });
  const out: Candidate[] = [];
  const add = (source: string, path: string, url: string | null = null, types = ["Front"], note: string | null = "") =>
    out.push(candidate(source, path, url, types, note));

  const caa = (name: string) => ((load(slug, name) as Caa | null)?.images ?? []).filter((i) => !i.image.endsWith(".pdf"));
  for (const i of caa(`caa_release_${choice.release}`)) {
    const p = await get(i.image, `${d}/caa-release-${tail(i.image)}`);
    add("Cover Art Archive (release)", p, i.image, i.types, i.comment || "");
  }
  type Sibling = { id: string; evidence: string[]; title: string | null };
  const rep = (load(slug, "edition-report") || {}) as { candidates?: Sibling[] };
  for (const sib of rep.candidates ?? []) {
    const same = sib.evidence.includes("RED catalogue number") && sib.evidence.includes("track lengths");
    if (sib.id !== choice.release && same) {
      const j = `${RAW}/${slug}/caa_release_${sib.id}.json`;
      if (!existsSync(j)) {
        const r = await fetch(`https://coverartarchive.org/release/${sib.id}`, {
          headers: { "User-Agent": UA },
          signal: AbortSignal.timeout(60_000),
        });
        dump(j, { fetched: stamp(), data: r.ok ? ((await r.json()) as unknown) : null }, true);
      }
      for (const i of caa(`caa_release_${sib.id}`)) {
        if (i.front) {
          const p = await get(i.image, `${d}/caa-sibling-${tail(i.image)}`);
          const note = `release ${sib.id.slice(0, 8)} ${py(sib.title)}`;
          add("Cover Art Archive (same catalogue number)", p, i.image, i.types, note);
        }
      }
    }
  }
  for (const i of caa(`caa_rg_${choice.release_group}`)) {
    if (i.front && !out.some((c) => c.url === i.image)) {
      const p = await get(i.image, `${d}/caa-rg-${tail(i.image)}`);
      add("Cover Art Archive (release group)", p, i.image, i.types, i.comment || "");
    }
  }
  if (!existsSync(`${RAW}/${slug}/itunes.json`) || !existsSync(`${RAW}/${slug}/deezer.json`)) await stores(slug, choice);
  const it = load(slug, "itunes") as { artworkUrl100?: string | null; collectionName?: string | null } | null;
  if (truthy(it) && it?.artworkUrl100) {
    const u = it.artworkUrl100.replaceAll("100x100bb", "3000x3000bb");
    const note = "collectionName" in it ? (it.collectionName ?? null) : "";
    add("iTunes", await get(u, `${d}/itunes-3000.jpg`), u, undefined, note);
  }
  const dz = load(slug, "deezer") as { cover_xl?: string | null; title?: string | null } | null;
  if (truthy(dz) && dz?.cover_xl) {
    const note = "title" in dz ? (dz.title ?? null) : "";
    add("Deezer", await get(dz.cover_xl, `${d}/deezer-xl.jpg`), dz.cover_xl, undefined, note);
  }
  const db = inventory();
  const album = db.query<{ id: number }, [string]>("select id from albums where path = ?").get(choice.path);
  if (!album) throw new Error(`no album at ${choice.path}`);
  const pictures = db
    .query<{ sha256: string }, [number]>(
      "select distinct p.sha256 from pictures p join files f on f.id = p.file_id where f.album_id = ? and p.type = 3",
    )
    .all(album.id);
  for (const { sha256: h } of pictures) add("files (embedded)", blob(h));
  const extras = db
    .query<{ relpath: string; sha256: string }, [number]>(
      `select relpath, sha256 from extras where album_id = ? and (lower(relpath) like '%.jpg' or lower(relpath) like '%.jpeg'
      or lower(relpath) like '%.png')`,
    )
    .all(album.id);
  for (const { relpath, sha256: h } of extras) add("files (folder)", blob(h), undefined, undefined, relpath);
  const prev = existsSync(`${d}/candidates.json`) ? readJson<Candidate[]>(`${d}/candidates.json`) : [];
  const kept = prev.filter((c) => /^(added|upscaled)-/.test(basename(c.path)) && !out.some((x) => x.id === c.id));
  dump(`${d}/candidates.json`, [...out, ...kept]);
  return [...out, ...kept];
}

function previews(slug: string, cands: Candidate[], outdir: string): void {
  mkdirSync(outdir, { recursive: true });
  cands.forEach((c, n) => {
    if (c.types.includes("Front")) {
      capture(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", `${META}/${c.path}`, "-vf", "scale='min(700,iw)':'min(700,ih)':force_original_aspect_ratio=decrease", "-frames:v", "1", "-q:v", "3", `${outdir}/${slug}-${n}.jpg`]);
    }
  });
}

export function embed(src: string, dest: string): void {
  const ppm = `${dest}.ppm`;
  const px = Math.min(EMBED_PX, Math.max(...dims(src)));
  run([
    "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-vf",
    `scale=${px}:${px}:force_original_aspect_ratio=decrease:flags=lanczos+accurate_rnd+full_chroma_int`,
    "-pix_fmt", "rgb24", "-frames:v", "1", ppm,
  ]);
  run([MOZJPEG, "-quality", String(EMBED_QUALITY), "-optimize", "-progressive", "-sample", "2x2", "-outfile", dest, ppm]);
  rmSync(ppm);
}

export function masterCopy(src: string, dest: string): string {
  const ppm = `${dest}.ppm`;
  const icc = `${dest}.icc`;
  run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-pix_fmt", "rgb24", "-frames:v", "1", ppm]);
  const profile = capture(["magick", src, "icc:-"]);
  const cmd = ["cjpeg", "-quality", String(MASTER_QUALITY), "-optimize", "-progressive", "-sample", "1x1", "-outfile", dest];
  if (profile.length) {
    writeFileSync(icc, profile);
    cmd.splice(1, 0, "-icc", icc);
  }
  run([...cmd, ppm]);
  for (const f of [ppm, icc]) if (existsSync(f)) rmSync(f);
  if (/\.jpe?g$/.test(src.toLowerCase()) && size(src) <= size(dest)) {
    writeFileSync(dest, readFileSync(src));
    return "original file, already smaller than a quality 95 re-encode";
  }
  return `quality ${MASTER_QUALITY}, 4:4:4, colour profile kept`;
}

function choose(slug: string, cid: string, why: string, keep = false, wait = false): void {
  const cands = readJson<Candidate[]>(`${RAW}/${slug}/covers/candidates.json`);
  const c = cands.find((x) => x.id === cid);
  if (!c) throw new Error(`no candidate ${cid} for ${slug}`);
  const d = `${CATALOGUE}/covers/${slug}`;
  mkdirSync(d, { recursive: true });
  const src = `${META}/${c.path}`;
  const master = `${d}/cover.jpg`;
  for (const old of readdirSync(d)) if (old.startsWith("cover.") && old !== "cover.jpg") rmSync(`${d}/${old}`);
  const method = masterCopy(src, master);
  const small = `${d}/embed-${EMBED_PX}.jpg`;
  embed(src, small);
  const entry = {
    chosen: c,
    why,
    master: relative(META, master),
    master_bytes: size(master),
    master_method: method,
    embed: relative(META, small),
    embed_bytes: size(small),
    embed_size: dims(small),
  };
  const p = `${CATALOGUE}/covers.json`;
  const lock = `${p}.lock`;
  for (;;) {
    try {
      closeSync(openSync(lock, "wx"));
      break;
    } catch {
      if (Date.now() - (statSync(lock, { throwIfNoEntry: false })?.mtimeMs ?? Date.now()) > 30_000) rmSync(lock, { force: true });
      Bun.sleepSync(50);
    }
  }
  try {
    const all = existsSync(p) ? readJson<Record<string, unknown>>(p) : {};
    all[slug] = entry;
    dump(`${p}.tmp`, all);
    renameSync(`${p}.tmp`, p);
  } finally {
    rmSync(lock, { force: true });
  }
  if (!keep) autoUpscale(slug, c, cands, wait);
  const kb = (n: number) => Math.floor(n / 1024);
  console.log([slug, c.width, "x", c.height, kb(c.bytes), "KB ->", kb(size(master)), "KB", method].join(" "));
}

function autoUpscale(slug: string, c: Candidate, cands: Candidate[], wait = false): void {
  if (Math.max(c.width, c.height) >= AUTO_UPSCALE_BELOW || c.source.startsWith("Upscaled")) return;
  if (cands.some((x) => x.source === "Upscaled (ultrasharpv2)" && x.note?.startsWith(`${c.source} ${c.width}x${c.height}`))) return;
  const args = ["bun", `${import.meta.dir}/upscale.ts`, slug, c.id, "ultrasharpv2", "--master"];
  if (wait) {
    console.log(`upscaling ${c.width}x${c.height} with 4x-UltraSharpV2 and waiting for it`);
    const p = Bun.spawnSync(args, { stderr: "inherit", stdout: "inherit" });
    if (p.exitCode !== 0) throw new Error("upscale failed");
    return;
  }
  const log = Bun.file(`${RAW}/${slug}/covers/upscale.log`);
  const p = Bun.spawn(["bun", `${import.meta.dir}/upscale.ts`, slug, c.id, "ultrasharpv2", "--master"], { stdio: ["ignore", log, log], detached: true });
  p.unref();
  console.log(`upscaling ${c.width}x${c.height} with 4x-UltraSharpV2 in the background; it becomes the master when done (log in raw/${slug}/covers/upscale.log)`);
}

async function addCover(slug: string, url: string, source: string, note: string): Promise<void> {
  const d = `${RAW}/${slug}/covers`;
  const p = `${d}/added-${basename(url)}`;
  if (existsSync(url)) writeFileSync(p, readFileSync(url));
  else await get(url, p);
  const c = candidate(source, p, url, ["Front"], note);
  const cands = [...readJson<Candidate[]>(`${d}/candidates.json`).filter((x) => x.id !== c.id), c];
  dump(`${d}/candidates.json`, cands);
  console.log([c.id, `${c.width}x${c.height}`, Math.floor(c.bytes / 1024), "KB"].join(" "));
}

if (import.meta.main) {
  const [cmd, ...rest] = Bun.argv.slice(2);
  if (cmd === "choose" && rest.length >= 3) {
    choose(rest[0]!, rest[1]!, rest[2]!, rest.includes("--keep"), rest.includes("--wait"));
  } else if (cmd === "add" && rest.length >= 4) {
    await addCover(rest[0]!, rest[1]!, rest[2]!, rest[3]!);
  } else if (cmd && cmd !== "choose" && cmd !== "add") {
    const ch = readJson<Record<string, Choice>>(`${CATALOGUE}/editions.json`);
    for (const slug of rest.length ? rest : Object.keys(ch)) {
      const choice = ch[slug];
      if (!choice) throw new Error(`no edition chosen for ${slug}`);
      const cs = await candidates(slug, choice);
      previews(slug, cs, cmd);
      cs.forEach((c, n) => {
        if (c.types.includes("Front")) {
          const line = [slug, n, c.source, `${c.width}x${c.height}`, Math.floor(c.bytes / 1024), "KB", py(c.note)];
          console.log(line.join(" "));
        }
      });
    }
  } else {
    console.error("usage: covers [slug...] | add <slug> <url> <source> <note> | choose <slug> <candidate-id> <why> [--keep] [--wait]");
    process.exit(1);
  }
}
