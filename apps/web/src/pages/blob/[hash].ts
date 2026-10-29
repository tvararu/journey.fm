import type { APIRoute } from "astro";

import { INVENTORY } from "@/lib/paths";

const HASH = /^[0-9a-f]{64}$/;
const EXTS = [".jpg", ".jpeg", ".png", ".gif", ".bin"];

export const GET: APIRoute = async ({ params }) => {
  const hash = params["hash"] ?? "";
  if (!HASH.test(hash)) return new Response("not found", { status: 404 });
  for (const ext of EXTS) {
    const file = Bun.file(`${INVENTORY}/blobs/${hash}${ext}`);
    if (await file.exists()) {
      return new Response(file, { headers: { "Cache-Control": "max-age=31536000, immutable" } });
    }
  }
  return new Response("not found", { status: 404 });
};
