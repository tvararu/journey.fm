import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

const N = 4096;
const WINDOWS = 48;
const JOBS = 4;
const HANN = Float64Array.from({ length: N }, (_, i) => 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (N - 1)));
const BITREV = Uint16Array.from({ length: N }, (_, i) => parseInt(i.toString(2).padStart(12, "0").split("").reverse().join(""), 2));
const TW_RE = Float64Array.from({ length: N / 2 }, (_, k) => Math.cos((-2 * Math.PI * k) / N));
const TW_IM = Float64Array.from({ length: N / 2 }, (_, k) => Math.sin((-2 * Math.PI * k) / N));

type Result =
  | { path: string; sr: number; quiet: true }
  | { path: string; sr: number; cliff_db: number; cliff_hz: number | null; ref: number; top: number }
  | { path: string; error: string };

class PyError extends Error {}

function fft(x: Float64Array): [Float64Array, Float64Array] {
  const re = new Float64Array(N);
  const im = new Float64Array(N);
  for (let i = 0; i < N; i++) re[i] = x[BITREV[i] as number] as number;
  for (let size = 2; size <= N; size *= 2) {
    const half = size / 2;
    const step = N / size;
    for (let start = 0; start < N; start += size) {
      for (let k = 0; k < half; k++) {
        const wr = TW_RE[k * step] as number;
        const wi = TW_IM[k * step] as number;
        const j = start + k + half;
        const br = re[j] as number;
        const bi = im[j] as number;
        const tr = wr * br - wi * bi;
        const ti = wr * bi + wi * br;
        const ur = re[start + k] as number;
        const ui = im[start + k] as number;
        re[start + k] = ur + tr;
        im[start + k] = ui + ti;
        re[j] = ur - tr;
        im[j] = ui - ti;
      }
    }
  }
  return [re, im];
}

async function output(cmd: string[]): Promise<Uint8Array> {
  const proc = Bun.spawn(cmd, { stdin: "ignore", stdout: "pipe", stderr: "ignore" });
  const data = new Uint8Array(await new Response(proc.stdout).arrayBuffer());
  await proc.exited;
  return data;
}

async function spectrum(p: string): Promise<[number, number[] | null]> {
  const text = new TextDecoder().decode(await output(["ffprobe", "-v", "quiet", "-of", "json", "-show_streams", "-select_streams", "a:0", p]));
  if (!text.trim()) throw new PyError("JSONDecodeError('Expecting value: line 1 column 1 (char 0)')");
  const probe = JSON.parse(text) as { streams?: { sample_rate?: string }[] };
  if (!probe.streams) throw new PyError("KeyError('streams')");
  const stream = probe.streams[0];
  if (!stream) throw new PyError("IndexError('list index out of range')");
  if (stream.sample_rate === undefined) throw new PyError("KeyError('sample_rate')");
  const sr = parseInt(stream.sample_rate, 10);
  const raw = await output(["ffmpeg", "-v", "quiet", "-i", p, "-ac", "1", "-f", "s16le", "-"]);
  const pcm = new Int16Array(raw.slice(0, Math.floor(raw.length / 2) * 2).buffer);
  const total = pcm.length;
  if (total < N * 4) return [sr, null];
  const power = new Float64Array(N / 2);
  let used = 0;
  const seg = new Float64Array(N);
  for (let w = 0; w < WINDOWS; w++) {
    const s = Math.trunc(((total - N) * (w + 0.5)) / WINDOWS);
    let peak = 0;
    for (let i = 0; i < N; i += 16) peak = Math.max(peak, Math.abs(pcm[s + i] as number));
    if (peak < 300) continue;
    for (let i = 0; i < N; i++) seg[i] = (pcm[s + i] as number) * (HANN[i] as number);
    const [re, im] = fft(seg);
    for (let k = 0; k < N / 2; k++) {
      const m = Math.hypot(re[k] as number, im[k] as number);
      power[k] = (power[k] as number) + m * m;
    }
    used++;
  }
  if (!used) return [sr, null];
  return [sr, Array.from(power, (v) => 10 * Math.log10(v / used + 1e-9))];
}

function pySum(v: number[]): number {
  let s = 0;
  let c = 0;
  for (const x of v) {
    const t = s + x;
    c += Math.abs(s) >= Math.abs(x) ? s - t + x : x - t + s;
    s = t;
  }
  return c && Number.isFinite(c) ? s + c : s;
}

function band(db: number[], sr: number, lo: number, hi: number): number {
  const v = db.slice(Math.trunc((lo * N) / sr), Math.trunc((hi * N) / sr));
  if (!v.length) throw new PyError("ZeroDivisionError('division by zero')");
  return pySum(v) / v.length;
}

function round1(x: number): number {
  if (Number.isInteger(x * 4) && !Number.isInteger(x * 2)) {
    const lo = Math.floor(x * 10);
    return (lo % 2 === 0 ? lo : lo + 1) / 10;
  }
  return Number(x.toFixed(1));
}

async function measure(p: string): Promise<Result> {
  try {
    const [sr, db] = await spectrum(p);
    if (db === null) return { path: p, sr, quiet: true };
    const top = Math.min(sr / 2 - 300, 23000);
    let cliff = 0;
    let at: number | null = null;
    for (let f = 14000; f + 600 <= top; f += 100) {
      const d = band(db, sr, f - 600, f) - band(db, sr, f, f + 600);
      if (d > cliff) {
        cliff = d;
        at = f;
      }
    }
    return { path: p, sr, cliff_db: round1(cliff), cliff_hz: at, ref: round1(band(db, sr, 2000, 4000)), top: round1(band(db, sr, top - 1000, top)) };
  } catch (e) {
    return { path: p, error: e instanceof PyError ? e.message : `${e instanceof Error ? e.name : "Error"}(${JSON.stringify(String(e))})` };
  }
}

const float = (x: number) => (Object.is(x, -0) ? "-0.0" : Number.isInteger(x) ? `${x}.0` : String(x));

function dumps(r: Result): string {
  const fields = Object.entries(r).map(([k, v]) => {
    const s = typeof v === "number" && (k === "cliff_db" || k === "ref" || k === "top") ? float(v) : JSON.stringify(v);
    return `${JSON.stringify(k)}: ${s}`;
  });
  return `{${fields.join(", ")}}`;
}

const [input, out] = Bun.argv.slice(2);
if (!input || !out) {
  console.error("usage: spectral.ts <paths.txt> <out.jsonl>");
  process.exit(1);
}
const text = readFileSync(input, "utf8").replace(/\r\n?/g, "\n");
const paths = text.split("\n");
if (text.endsWith("\n") || text === "") paths.pop();
writeFileSync(out, "");
let next = 0;
await Promise.all(
  Array.from({ length: JOBS }, async () => {
    while (next < paths.length) {
      const r = await measure(paths[next++] as string);
      appendFileSync(out, `${dumps(r)}\n`);
    }
  }),
);
