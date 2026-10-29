import type { APIRoute } from "astro";

import { DATA } from "@/lib/paths";
import { addNote, coverCandidates } from "@/lib/records";
import { UPSCALERS, type Upscaler, upscale } from "@/lib/upscale";

export const POST: APIRoute = async ({ request, redirect, cookies }) => {
  const form = await request.formData();
  const slug = String(form.get("slug") ?? "");
  const album = String(form.get("album") ?? "");
  const id = String(form.get("candidate") ?? "");
  const which = String(form.get("upscaler") ?? "") as Upscaler;
  const back = String(form.get("back") ?? "/");
  const cands = await coverCandidates(slug);
  const c = cands.find((x) => x.id === id);
  if (!(c && which in UPSCALERS)) return new Response("unknown candidate or upscaler", { status: 400 });
  const made = await upscale(slug, c, which);
  const path = `${DATA}/raw/${slug}/covers/candidates.json`;
  await Bun.write(path, JSON.stringify([...cands.filter((x) => x.id !== made.id), made], null, 1));
  const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
  await addNote({ album, at, by: "deity", text: `Upscaled the ${c.source} cover (${c.width}x${c.height}) with ${UPSCALERS[which].label} to ${made.width}x${made.height}.` });
  cookies.set("flash", `Upscaled with ${UPSCALERS[which].label}`, { maxAge: 60, path: "/" });
  return redirect(`${back.startsWith("/album/") ? back : "/"}#cover`, 303);
};
