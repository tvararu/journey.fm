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
