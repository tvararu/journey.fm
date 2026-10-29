import { realpathSync } from "node:fs";
import { join } from "node:path";
import type { APIRoute } from "astro";

import { DATA } from "@/lib/paths";

const TEXT = /\.(html|log)$/i;

export const GET: APIRoute = async ({ params }) => {
  const root = realpathSync(DATA);
  let full: string;
  try {
    full = realpathSync(join(root, params["path"] ?? ""));
  } catch {
    return new Response("not found", { status: 404 });
  }
  const file = Bun.file(full);
  const allowed = full.includes("/covers/") || full.includes("/blobs/") || full.startsWith(`${root}/raw/`);
  if (!full.startsWith(`${root}/`) || !allowed || !(await file.exists())) {
    return new Response("not found", { status: 404 });
  }
  const text = TEXT.test(full) ? { "Content-Type": "text/plain; charset=utf-8" } : undefined;
  return new Response(file, { headers: text ?? {} });
};
