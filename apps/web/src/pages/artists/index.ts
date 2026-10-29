import type { APIRoute } from "astro";

import { library } from "@/lib/library";

export const GET: APIRoute = async () => {
  const first = (await library())[0];
  return new Response(null, {
    status: 302,
    headers: { Location: first ? `/artists/${encodeURIComponent(first.artist_dir)}` : "/" },
  });
};
