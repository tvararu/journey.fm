import { py } from "./py";

export const UA = "journey.fm/0.1 ( private )";
export const REL_INC = "labels+recordings+media+isrcs+url-rels+genres+tags+release-groups+artist-credits+discids";
const RETRY = new Set([429, 500, 502, 503, 504]);
const last = new Map<string, number>();

const quotePlus = (s: string): string =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`).replace(/%20/g, "+");

export const urlencode = (q: Record<string, unknown>): string =>
  Object.entries(q).map(([k, v]) => `${quotePlus(k)}=${quotePlus(py(v))}`).join("&");

export async function fetchJson<T>(url: string, gap: number, headers: Record<string, string> = {}): Promise<T | null> {
  const host = new URL(url).host;
  const wait = (last.get(host) ?? 0) + gap * 1000 - Date.now();
  if (wait > 0) await Bun.sleep(wait);
  for (let attempt = 0; attempt < 4; attempt++) {
    last.set(host, Date.now());
    const r = await fetch(url, { headers: { "User-Agent": UA, ...headers }, signal: AbortSignal.timeout(30_000) }).catch(() => null);
    if (!r) {
      await Bun.sleep(3000 * (attempt + 1));
      continue;
    }
    if (r.ok) return (await r.json()) as T;
    if (r.status === 400 || r.status === 404) return null;
    if (!RETRY.has(r.status)) throw new Error(`HTTP ${r.status} ${r.statusText} for ${url}`);
    await Bun.sleep(3000 * (attempt + 1));
  }
  console.error("gave up on", url);
  return null;
}

export const mb = <T>(path: string, q: Record<string, unknown> = {}): Promise<T | null> =>
  fetchJson<T>(`https://musicbrainz.org/ws/2/${path}?${urlencode({ ...q, fmt: "json" })}`, 1.1);

export async function red<T>(q: Record<string, unknown>): Promise<T | null> {
  const key = process.env["REDACTED_API_KEY"] ?? "";
  const r = await fetchJson<{ response?: T }>(`https://redacted.sh/ajax.php?${urlencode(q)}`, 2.3, { Authorization: key });
  return r ? (r.response ?? null) : null;
}
