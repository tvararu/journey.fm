import { realpathSync } from "node:fs";
import { join } from "node:path";
import type { APIRoute } from "astro";

import { DATA } from "@/lib/paths";

export const GET: APIRoute = async ({ params }) => {
  const root = realpathSync(DATA);
  let full: string;
  try {
    full = realpathSync(join(root, params["path"] ?? ""));
  } catch {
    return new Response("not found", { status: 404 });
  }
  const file = Bun.file(full);
  if (!full.startsWith(`${root}/`) || !full.includes("/covers/") || !(await file.exists())) {
    return new Response("not found", { status: 404 });
  }
  return new Response(file);
};
