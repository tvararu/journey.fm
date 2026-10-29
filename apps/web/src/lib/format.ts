import type { Value } from "./records";

export function clock(seconds: number): string {
  const s = seconds % 60;
  return `${Math.floor(seconds / 60)}:${s.toFixed(1).padStart(4, "0")}`;
}

export function show(v: Value | undefined): string {
  if (v === null || v === undefined || v === "") return "-";
  return Array.isArray(v) ? v.join(", ") : String(v);
}

function asList(v: Value | undefined): string[] {
  if (v === null || v === undefined || v === "") return [];
  return Array.isArray(v) ? v.map(String).sort() : [String(v)];
}

export function same(a: Value | undefined, b: Value | undefined): boolean {
  const x = asList(a);
  const y = asList(b);
  return x.length === y.length && x.every((v, i) => v === y[i]);
}

export function empty(v: Value | undefined): boolean {
  return asList(v).length === 0;
}

export function format(codec: string, bits: string, sr: string): string {
  const rates = sr
    .split(",")
    .filter(Boolean)
    .map((x) => String(Number(x) / 1000))
    .join(", ");
  return `${codec.toUpperCase()} ${bits}/${rates}`;
}

const BLOCKS: Record<number, string> = {
  0: "STREAMINFO",
  1: "PADDING",
  2: "APP",
  3: "SEEKTABLE",
  4: "VORBIS",
  5: "CUESHEET",
  6: "PICTURE",
};

export function blocks(json: string | null): string {
  const list = (json ? JSON.parse(json) : []) as [number, number][];
  return list.map(([t, n]) => `${BLOCKS[t] ?? t}(${n})`).join(" ");
}

export function size(bytes: number): string {
  return bytes >= 1e9 ? `${(bytes / 1e9).toFixed(2)} GB` : `${(bytes / 1e6).toFixed(0)} MB`;
}

type Audio = { codec: string; bits: number | null; sample_rate: number; size: number; duration: number | null };

export function quality(files: Audio[]): string {
  const kinds = new Map<string, number>();
  for (const f of files) {
    const k = `${f.codec.toUpperCase()} ${f.bits ? `${f.bits}-bit` : ""} ${f.sample_rate / 1000} kHz`.replace(/\s+/g, " ");
    kinds.set(k, (kinds.get(k) ?? 0) + 1);
  }
  const bytes = files.reduce((s, f) => s + f.size, 0);
  const secs = files.reduce((s, f) => s + (f.duration ?? 0), 0);
  const kbps = secs ? Math.round((bytes * 8) / secs / 1000) : 0;
  const parts = [...kinds].map(([k, n]) => (kinds.size > 1 ? `${k} ×${n}` : k));
  return `${parts.join(", ")} · ${kbps} kbps average`;
}

export function mmss(s: number): string {
  const t = Math.round(s);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
}

export function mins(s: number): string {
  const m = Math.round(s / 60);
  return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`;
}

export function minsec(s: number): string {
  const t = Math.round(s);
  return `${Math.floor(t / 60)} min ${t % 60} s`;
}

export function audio(bits: string, sr: string): string {
  if (bits.includes(",") || sr.includes(",")) return "mixed";
  return `${bits}/${Number(sr) / 1000}`;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function day(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]}` : iso;
}

export function stamp(at: string): string {
  const m = /^\d{4}-\d{2}-\d{2}[T ](\d{2}:\d{2})/.exec(at);
  return m ? `${day(at)} ${m[1]}` : day(at);
}

export function when(at: string): string {
  const today = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/London" });
  const m = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/.exec(at);
  return m && m[1] === today ? m[2]! : day(at);
}

export function redTail(name: string): string {
  return name.replace(/^.*\)\s*/, "").replace(/^[-\s]+/, "").replace(/[[\]]/g, "").trim() || "copy";
}

export function dots(n: number, total: number, width = 20): { on: string; off: string } {
  const k = total ? Math.min(width, Math.max(n > 0 ? 1 : 0, Math.round((n / total) * width))) : 0;
  return { on: "▪".repeat(k), off: "·".repeat(width - k) };
}
