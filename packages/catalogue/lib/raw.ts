import { existsSync, mkdirSync, readFileSync } from "node:fs";

import { RAW } from "./paths";
import { dump, stamp } from "./py";

export function save<T>(slug: string, name: string, data: T): T {
  mkdirSync(`${RAW}/${slug}`, { recursive: true });
  dump(`${RAW}/${slug}/${name}.json`, { fetched: stamp(), data: data === undefined ? null : data });
  return data;
}

export function load(slug: string, name: string): unknown {
  const p = `${RAW}/${slug}/${name}.json`;
  if (!existsSync(p)) return null;
  const d = JSON.parse(readFileSync(p, "utf8")) as unknown;
  if (d && typeof d === "object" && !Array.isArray(d)) {
    const keys = Object.keys(d);
    if (keys.length === 2 && "fetched" in d && "data" in d) return d.data;
  }
  return d;
}
