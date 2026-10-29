import type { APIRoute } from "astro";

import { library } from "@/lib/library";

export const GET: APIRoute = async () => {
  const rows = await library();
  const counts = new Map<string, number>();
  for (const r of rows) counts.set(r.artist_dir, (counts.get(r.artist_dir) ?? 0) + 1);
  const body = {
    albums: rows.map((r) => ({ id: r.id, title: r.title, artist: r.artist, state: r.state })),
    artists: [...counts].sort((a, b) => a[0].localeCompare(b[0])).map(([name, n]) => ({ name, n })),
  };
  return new Response(JSON.stringify(body), { headers: { "content-type": "application/json" } });
};
