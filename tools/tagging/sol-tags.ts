import { lstatSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = "/mnt/pool";
const AUDIO = [".flac", ".mp3", ".m4a", ".ogg", ".opus"];

class Float {
  constructor(readonly value: number) {}
}

type Json = string | number | boolean | null | Float | Json[] | { [k: string]: Json };
type Stream = { codec_type?: string; codec_name?: string; sample_rate?: string; bits_per_raw_sample?: string; bits_per_sample?: number; width?: number; height?: number };
type Probe = { format?: { duration?: string; bit_rate?: string; tags?: Record<string, string> }; streams?: Stream[] };

const byCodePoint = (a: string, b: string) => Buffer.compare(Buffer.from(a), Buffer.from(b));
const isAudio = (f: string) => AUDIO.some((e) => f.toLowerCase().endsWith(e));

function float(x: number): string {
  if (Object.is(x, -0)) return "-0.0";
  if (!Number.isFinite(x)) return Number.isNaN(x) ? "NaN" : x > 0 ? "Infinity" : "-Infinity";
  const [m = "", e = "0"] = x.toExponential().split("e");
  const exp = Number(e);
  const sign = m.startsWith("-") ? "-" : "";
  const digits = m.replace(/^-/, "").replace(".", "");
  if (exp < -4 || exp >= 16) return `${sign}${digits[0]}${digits.length > 1 ? `.${digits.slice(1)}` : ""}e${exp < 0 ? "-" : "+"}${String(Math.abs(exp)).padStart(2, "0")}`;
  if (exp < 0) return `${sign}0.${"0".repeat(-exp - 1)}${digits}`;
  const int = digits.slice(0, exp + 1).padEnd(exp + 1, "0");
  return `${sign}${int}.${digits.slice(exp + 1) || "0"}`;
}

function dumps(v: Json): string {
  if (v instanceof Float) return float(v.value);
  if (Array.isArray(v)) return `[${v.map(dumps).join(", ")}]`;
  if (v !== null && typeof v === "object") return `{${Object.entries(v).map(([k, x]) => `${JSON.stringify(k)}: ${dumps(x)}`).join(", ")}}`;
  return JSON.stringify(v);
}

function probe(p: string): Probe {
  const out = Bun.spawnSync(["ffprobe", "-v", "quiet", "-of", "json", "-show_format", "-show_streams", p], { stderr: "ignore" }).stdout.toString();
  return JSON.parse(out || "{}") as Probe;
}

function walk(top: string): string[] {
  let names: string[];
  try {
    names = readdirSync(top);
  } catch {
    return [];
  }
  const out: string[] = [];
  for (const name of names) {
    const p = join(top, name);
    let dir = false;
    try {
      dir = statSync(p).isDirectory();
    } catch {}
    if (!dir) out.push(p);
    else if (!lstatSync(p).isSymbolicLink()) out.push(...walk(p));
  }
  return out;
}

function folder(rel: string): Json {
  const d = `${ROOT}/${rel}`;
  const files = walk(d).sort(byCodePoint);
  const tracks: Json[] = files.filter(isAudio).map((f) => {
    const p = probe(f);
    const streams = p.streams ?? [];
    const a = streams.find((s) => s.codec_type === "audio") ?? {};
    const v = streams.find((s) => s.codec_type === "video");
    const fmt = p.format ?? {};
    return {
      file: relative(d, f),
      codec: a.codec_name ?? null,
      sample_rate: a.sample_rate ?? null,
      bits: (a.bits_per_raw_sample || a.bits_per_sample) ?? null,
      bitrate: fmt.bit_rate ?? null,
      duration: new Float(fmt.duration ? Number(fmt.duration) : 0),
      tags: Object.fromEntries(Object.entries(fmt.tags ?? {}).map(([k, x]) => [k.toUpperCase(), x])),
      picture: v ? `${v.width ?? "None"}x${v.height ?? "None"} ${v.codec_name ?? "None"}` : null,
    };
  });
  return { path: rel, files: files.filter((f) => !isAudio(f)).map((f) => relative(d, f)), tracks };
}

const input = Bun.argv[2];
if (!input) {
  console.error("usage: sol-tags.ts <slug-to-dirs.json>");
  process.exit(1);
}
const albums = JSON.parse(readFileSync(input, "utf8")) as Record<string, string[]>;
const out: Record<string, Json> = {};
for (const [slug, rels] of Object.entries(albums)) out[slug] = rels.map(folder);
process.stdout.write(dumps(out));
