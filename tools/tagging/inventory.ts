import { Database } from "bun:sqlite";
import { closeSync, existsSync, fstatSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, readSync, statSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = process.env["JOURNEY_LIBRARY"] ?? "";
if (!ROOT) throw new Error("JOURNEY_LIBRARY is not set: the folder that holds Music");
const COLLECTIONS = ["Music"];
const AUDIO = [".flac", ".mp3", ".m4a", ".ogg", ".opus"];
const KEEP = [".jpg", ".jpeg", ".png", ".gif", ".log", ".cue", ".txt", ".nfo", ".m3u", ".m3u8", ".accurip"];
const OUT = Bun.argv[2];
if (!OUT) {
  console.error("usage: inventory.ts <out-dir>");
  process.exit(1);
}
const BLOBS = `${OUT}/blobs`;

const SCHEMA = `
create table albums (id integer primary key, collection text, path text unique, artist_dir text, album_dir text);
create table files (id integer primary key, album_id integer, relpath text, size integer, mtime real, codec text,
  sample_rate integer, bits integer, channels integer, samples integer, duration real, bitrate integer,
  audio_md5 text, vendor text, id3v2 integer, id3v1 integer, blocks text, error text);
create table tags (file_id integer, idx integer, key text, value text);
create table pictures (file_id integer, idx integer, type integer, mime text, description text,
  width integer, height integer, depth integer, size integer, sha256 text);
create table extras (album_id integer, relpath text, size integer, mtime real, sha256 text);
create table meta (key text primary key, value text);
`;

type Value = string | number | null;
type Picture = [Value, string, string, Value, Value, Value, number, string | null];
type Scan = {
  codec?: string | null;
  sample_rate?: number | null;
  bits?: number | null;
  channels?: number | null;
  samples?: number;
  duration?: number | null;
  bitrate?: number | null;
  audio_md5?: string;
  vendor?: string | null;
  id3v2?: number;
  id3v1?: number;
  blocks?: [number, number][] | null;
  tags: [string, string][];
  pictures: Picture[];
};
type Stream = { codec_type?: string; codec_name?: string; sample_rate?: string; bits_per_raw_sample?: string; bits_per_sample?: number; channels?: number; width?: number; height?: number; tags?: Record<string, string> };
type Probe = { format?: { duration?: string; bit_rate?: string; tags?: Record<string, string> }; streams?: Stream[] };

class PyError extends Error {}

const utf8 = new TextDecoder("utf-8", { ignoreBOM: true });
const sha256 = (data: Uint8Array) => new Bun.CryptoHasher("sha256").update(data).digest("hex");
const byCodePoint = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));
const lower = (name: string) => name.toLowerCase();
const endsWith = (name: string, exts: string[]) => exts.some((e) => lower(name).endsWith(e));

function blob(data: Uint8Array, ext: string): string {
  const h = sha256(data);
  const p = `${BLOBS}/${h}${ext}`;
  if (!existsSync(p)) writeFileSync(p, data);
  return h;
}

function extFor(mime: string): string {
  return ({ "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/gif": ".gif" } as Record<string, string>)[mime.toLowerCase()] ?? ".bin";
}

function int(b: Uint8Array, start: number, end: number, little = false): bigint {
  const s = b.subarray(start, end);
  let x = 0n;
  for (let i = 0; i < s.length; i++) x = (x << 8n) | BigInt(s[little ? s.length - 1 - i : i] ?? 0);
  return x;
}

const u32 = (b: Uint8Array, o: number, little = false) => Number(int(b, o, o + 4, little));
const ascii = (b: Uint8Array) => Array.from(b, (c) => (c < 0x80 ? String.fromCharCode(c) : "�")).join("");
const hex = (b: Uint8Array) => Buffer.from(b).toString("hex");

function partition(s: string, sep: string): [string, string] {
  const i = s.indexOf(sep);
  return i < 0 ? [s, ""] : [s.slice(0, i), s.slice(i + sep.length)];
}

function flac(path: string): Scan {
  const r: Scan = { codec: "flac", tags: [], pictures: [], blocks: [], id3v2: 0, id3v1: 0 };
  const blocks: [number, number][] = [];
  r.blocks = blocks;
  const fd = openSync(path, "r");
  try {
    const size = fstatSync(fd).size;
    let pos = 0;
    const read = (n: number) => {
      const buf = Buffer.alloc(Math.max(0, Math.min(n, size - pos)));
      const got = buf.length ? readSync(fd, buf, 0, buf.length, pos) : 0;
      pos += got;
      return new Uint8Array(buf.buffer, buf.byteOffset, got);
    };
    const head = read(10);
    if (ascii(head.subarray(0, 3)) === "ID3") {
      const at = (i: number) => {
        const v = head[i];
        if (v === undefined) throw new PyError("IndexError('index out of range')");
        return v;
      };
      const n = (at(6) << 21) | (at(7) << 14) | (at(8) << 7) | at(9);
      r.id3v2 = 1;
      pos = 10 + n + (at(5) & 0x10 ? 10 : 0);
    } else {
      pos = 0;
    }
    if (ascii(read(4)) !== "fLaC") throw new PyError("ValueError('no fLaC marker')");
    let d = new Uint8Array(0);
    while (true) {
      const h = read(4);
      const h0 = h[0];
      if (h0 === undefined) throw new PyError("IndexError('index out of range')");
      const last = h0 & 0x80;
      const t = h0 & 0x7f;
      const n = Number(int(h, 1, h.length));
      blocks.push([t, n]);
      if (t === 0 || t === 4 || t === 6) d = read(n);
      else pos += n;
      if (t === 0) {
        const x = int(d, 10, 18);
        const sr = Number(x >> 44n);
        const samples = Number(x & 0xfffffffffn);
        r.sample_rate = sr;
        r.channels = Number((x >> 41n) & 7n) + 1;
        r.bits = Number((x >> 36n) & 31n) + 1;
        r.samples = samples;
        r.audio_md5 = hex(d.subarray(18, 34));
        r.duration = sr ? samples / sr : null;
      } else if (t === 4) {
        let o = 4 + u32(d, 0, true);
        r.vendor = utf8.decode(d.subarray(4, o));
        const count = u32(d, o, true);
        o += 4;
        for (let i = 0; i < count; i++) {
          const n2 = u32(d, o, true);
          const s = utf8.decode(d.subarray(o + 4, o + 4 + n2));
          o += 4 + n2;
          r.tags.push(partition(s, "="));
        }
      } else if (t === 6) {
        const ptype = u32(d, 0);
        let o = 4;
        const ml = u32(d, o);
        const mime = ascii(d.subarray(o + 4, o + 4 + ml));
        o += 4 + ml;
        const dl = u32(d, o);
        const desc = utf8.decode(d.subarray(o + 4, o + 4 + dl));
        o += 4 + dl;
        const size = u32(d, o + 16);
        const data = d.subarray(o + 20, o + 20 + size);
        r.pictures.push([ptype, mime, desc, u32(d, o), u32(d, o + 4), u32(d, o + 8), size, blob(data, extFor(mime))]);
      }
      if (last) break;
    }
    if (size < 128) throw new PyError("OSError(22, 'Invalid argument')");
    pos = size - 128;
    r.id3v1 = ascii(read(3)) === "TAG" ? 1 : 0;
  } finally {
    closeSync(fd);
  }
  return r;
}

const truthy = (v: unknown) => v !== undefined && v !== null && v !== "" && v !== 0;
const toInt = (v: unknown) => (truthy(v) ? Math.trunc(Number(v)) : 0) || null;

function lossy(path: string): Scan {
  const out = Bun.spawnSync(["ffprobe", "-v", "quiet", "-of", "json", "-show_format", "-show_streams", path], { stderr: "ignore" }).stdout.toString();
  const p = JSON.parse(out || "{}") as Probe;
  const fmt = p.format ?? {};
  const streams = p.streams ?? [];
  const a = streams.find((s) => s.codec_type === "audio") ?? {};
  const r: Scan = {
    codec: a.codec_name ?? null,
    sample_rate: toInt(a.sample_rate),
    bits: toInt(truthy(a.bits_per_raw_sample) ? a.bits_per_raw_sample : a.bits_per_sample),
    channels: a.channels ?? null,
    duration: (truthy(fmt.duration) ? Number(fmt.duration) : 0) || null,
    bitrate: toInt(fmt.bit_rate),
    vendor: a.tags?.encoder ?? null,
    tags: Object.entries(fmt.tags ?? {}),
    pictures: [],
    blocks: null,
  };
  streams
    .filter((x) => x.codec_type === "video")
    .forEach((s, i) => {
      const data = Bun.spawnSync(["ffmpeg", "-nostdin", "-v", "quiet", "-i", path, "-map", `0:v:${i}`, "-c", "copy", "-f", "image2pipe", "-"], {
        stderr: "ignore",
      }).stdout;
      const mime = ({ mjpeg: "image/jpeg", png: "image/png" } as Record<string, string>)[s.codec_name ?? ""] ?? s.codec_name ?? "";
      r.pictures.push([null, mime, s.tags?.comment ?? "", s.width ?? null, s.height ?? null, null, data.length, data.length ? blob(data, extFor(mime)) : null]);
    });
  return r;
}

function pyList(v: unknown): string {
  return Array.isArray(v) ? `[${v.map(pyList).join(", ")}]` : String(v);
}

function scannedAt(): string {
  const d = new Date();
  const p = (n: number) => String(Math.trunc(Math.abs(n))).padStart(2, "0");
  const off = -d.getTimezoneOffset();
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}${off < 0 ? "-" : "+"}${p(off / 60)}${p(off % 60)}`;
}

function fileStat(path: string): { size: number; mtime: number } {
  const st = statSync(path, { bigint: true });
  return { size: Number(st.size), mtime: Number(st.mtimeNs / 1_000_000_000n) + Number(st.mtimeNs % 1_000_000_000n) * 1e-9 };
}

function isDir(path: string): boolean {
  try {
    return statSync(path).isDirectory();
  } catch {
    return false;
  }
}

function walk(top: string, out: [string, string[]][]) {
  let names: string[];
  try {
    names = readdirSync(top);
  } catch {
    return;
  }
  const dirs: string[] = [];
  const files: string[] = [];
  for (const name of names) (isDir(join(top, name)) ? dirs : files).push(name);
  out.push([top, files]);
  for (const d of dirs) if (!lstatSync(join(top, d)).isSymbolicLink()) walk(join(top, d), out);
}

function repr(e: unknown): string {
  if (e instanceof PyError) return e.message;
  if (e instanceof Error) return `${e.name}(${JSON.stringify(e.message)})`;
  return String(e);
}

mkdirSync(BLOBS, { recursive: true });
const db = new Database(`${OUT}/inventory.sqlite`);
db.run(SCHEMA);
db.run("insert into meta values (?, ?)", ["scanned_at", scannedAt()]);
const insAlbum = db.prepare("insert into albums (collection, path, artist_dir, album_dir) values (?,?,?,?)");
const insExtra = db.prepare("insert into extras values (?,?,?,?,?)");
const insFile = db.prepare(`insert into files (album_id, relpath, size, mtime, codec, sample_rate, bits, channels,
  samples, duration, bitrate, audio_md5, vendor, id3v2, id3v1, blocks, error)
  values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
const insTag = db.prepare("insert into tags values (?,?,?,?)");
const insPicture = db.prepare("insert into pictures values (?,?,?,?,?,?,?,?,?,?)");
const albums = new Map<string, number>();

for (const c of COLLECTIONS) {
  const base = `${ROOT}/${c}`;
  const tree: [string, string[]][] = [];
  walk(base, tree);
  tree.sort((x, y) => byCodePoint(x[0], y[0]));
  for (const [dirpath, files] of tree) {
    const parts = (relative(base, dirpath) || ".").split("/");
    if (parts.length === 1 && parts[0] === ".") continue;
    const artist = parts[0] ?? "";
    const album = parts[1];
    db.run("begin");
    for (const name of [...files].sort(byCodePoint)) {
      const full = join(dirpath, name);
      const key = album !== undefined ? `${c}/${artist}/${album}` : `${c}/${artist}`;
      let aid = albums.get(key);
      if (aid === undefined) {
        aid = Number(insAlbum.run(c, key, artist, album ?? "").lastInsertRowid);
        albums.set(key, aid);
      }
      const rel = relative(`${ROOT}/${key}`, full);
      const st = fileStat(full);
      if (!endsWith(name, AUDIO)) {
        const data = readFileSync(full);
        const dot = name.replace(/^\.+/, "").lastIndexOf(".");
        const ext = dot < 0 ? "" : lower(name.replace(/^\.+/, "").slice(dot));
        const h = endsWith(name, KEEP) ? blob(data, ext) : sha256(data);
        insExtra.run(aid, rel, st.size, st.mtime, h);
        continue;
      }
      let r: Scan;
      let err: string | null = null;
      try {
        r = lower(name).endsWith(".flac") ? flac(full) : lossy(full);
      } catch (e) {
        r = { tags: [], pictures: [] };
        err = repr(e);
      }
      const bitrate = r.bitrate || (r.duration ? Math.trunc((st.size * 8) / r.duration) : null);
      const fid = insFile.run(
        aid,
        rel,
        st.size,
        st.mtime,
        r.codec ?? null,
        r.sample_rate ?? null,
        r.bits ?? null,
        r.channels ?? null,
        r.samples ?? null,
        r.duration ?? null,
        bitrate,
        r.audio_md5 ?? null,
        r.vendor ?? null,
        r.id3v2 ?? null,
        r.id3v1 ?? null,
        r.blocks != null ? pyList(r.blocks) : null,
        err,
      ).lastInsertRowid;
      r.tags.forEach(([k, v], i) => insTag.run(fid, i, k, v));
      r.pictures.forEach((p, i) => insPicture.run(fid, i, ...p));
    }
    db.run("commit");
    console.log(c, parts.join("/"));
  }
}
