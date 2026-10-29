import { writeFileSync } from "node:fs";

export function py(v: unknown): string {
  if (v === null || v === undefined) return "None";
  if (typeof v === "boolean") return v ? "True" : "False";
  return String(v);
}

export function truthy(v: unknown): boolean {
  if (Array.isArray(v) || v instanceof Uint8Array) return v.length > 0;
  if (v !== null && typeof v === "object") return Object.keys(v).length > 0;
  return Boolean(v);
}

export const basename = (p: string): string => p.slice(p.lastIndexOf("/") + 1);

export function fixed1(x: number): string {
  const q = x * 4;
  if (Number.isInteger(q) && q % 2 !== 0) {
    const n = Math.floor(x * 10);
    return ((n % 2 === 0 ? n : n + 1) / 10).toFixed(1);
  }
  return x.toFixed(1);
}

export function stamp(d = new Date()): string {
  const p = (n: number) => String(n).padStart(2, "0");
  const off = -d.getTimezoneOffset();
  const a = Math.abs(off);
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
    + `${off < 0 ? "-" : "+"}${p(Math.floor(a / 60))}${p(a % 60)}`;
}

export function dumps(data: unknown, ascii = false): string {
  const s = JSON.stringify(data, null, 1);
  return ascii ? s.replace(/[\u007f-￿]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`) : s;
}

export function dump(path: string, data: unknown, ascii = false): void {
  writeFileSync(path, dumps(data, ascii));
}

const ENTITIES: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "–", mdash: "—", lsquo: "‘",
  rsquo: "’", sbquo: "‚", ldquo: "“", rdquo: "”", bdquo: "„", hellip: "…", laquo: "«",
  raquo: "»", lsaquo: "‹", rsaquo: "›", middot: "·", bull: "•", times: "×", divide: "÷",
  deg: "°", copy: "©", reg: "®", trade: "™", iexcl: "¡", iquest: "¿", szlig: "ß",
  aelig: "æ", AElig: "Æ", oslash: "ø", Oslash: "Ø", eth: "ð", ETH: "Ð", thorn: "þ",
  THORN: "Þ", oelig: "œ", OElig: "Œ", euro: "€", pound: "£", yen: "¥", cent: "¢",
  sect: "§", para: "¶", dagger: "†", prime: "′", Prime: "″", minus: "−", shy: "­",
};
const MARKS: Record<string, string> = {
  acute: "́", grave: "̀", circ: "̂", uml: "̈", tilde: "̃", ring: "̊", cedil: "̧", caron: "̌",
};

const named = (e: string): string | undefined => {
  if (ENTITIES[e] !== undefined) return ENTITIES[e];
  const m = /^([A-Za-z])(acute|grave|circ|uml|tilde|ring|cedil|caron)$/.exec(e);
  return m ? (m[1]! + MARKS[m[2]!]!).normalize("NFC") : undefined;
};

export const unescapeHtml = (s: string): string =>
  s.replace(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (m, e: string) => {
    if (e[0] !== "#") return named(e) ?? m;
    const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
    return n === 0 || n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff) ? "�" : String.fromCodePoint(n);
  });

export function editDistance(a: string, b: string): number {
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const row = [i];
    for (let j = 1; j <= b.length; j++) row[j] = Math.min(prev[j]! + 1, row[j - 1]! + 1, prev[j - 1]! + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = row;
  }
  return prev[b.length]!;
}

export const squash = (s: string | null | undefined): string =>
  (s ?? "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");

export function similarTitle(a: string | null | undefined, b: string | null | undefined): boolean {
  const x = squash(a);
  const y = squash(b);
  return x === y || (x.length > 3 && editDistance(x, y) <= Math.max(2, x.length / 10));
}
