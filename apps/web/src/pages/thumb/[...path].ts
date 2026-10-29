import { createHash } from "node:crypto";
import { existsSync, mkdirSync, realpathSync, renameSync, statSync } from "node:fs";
import { join } from "node:path";
import type { APIRoute } from "astro";

import { DATA, INVENTORY } from "@/lib/paths";

const HASH = /^[0-9a-f]{64}$/;
const EXTS = [".jpg", ".jpeg", ".png", ".gif", ".bin"];
const notFound = () => new Response("not found", { status: 404 });

function source(path: string): string | null {
  const blob = /^blob\/([^/]+)$/.exec(path)?.[1];
  if (blob !== undefined) {
    if (!HASH.test(blob)) return null;
    const ext = EXTS.find((e) => existsSync(`${INVENTORY}/blobs/${blob}${e}`));
    return ext ? `${INVENTORY}/blobs/${blob}${ext}` : null;
  }
  const root = realpathSync(DATA);
  let full: string;
  try {
    full = realpathSync(join(root, path));
  } catch {
    return null;
  }
  const allowed = full.includes("/covers/") || full.includes("/blobs/") || full.startsWith(`${root}/raw/`);
  return full.startsWith(`${root}/`) && allowed ? full : null;
}

export const GET: APIRoute = ({ params }) => {
  const src = source(params["path"] ?? "");
  if (!src || !statSync(src, { throwIfNoEntry: false })?.isFile()) return notFound();
  const key = createHash("sha1").update(`${src}:${statSync(src).mtimeMs}`).digest("hex");
  mkdirSync(`${DATA}/thumbs`, { recursive: true });
  const cache = `${DATA}/thumbs/${key}.jpg`;
  if (!existsSync(cache)) {
    const tmp = `${cache}.tmp`;
    const made = Bun.spawnSync(["magick", `${src}[0]`, "-auto-orient", "-thumbnail", "480x480>", "-quality", "85", `jpg:${tmp}`]);
    if (made.exitCode !== 0) return new Response(made.stderr.toString().slice(0, 300), { status: 500 });
    renameSync(tmp, cache);
  }
  return new Response(Bun.file(cache), {
    headers: { "Cache-Control": "public, max-age=31536000, immutable", "Content-Type": "image/jpeg" },
  });
};
