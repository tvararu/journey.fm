import type { APIRoute } from "astro";

import { addReview, fingerprint } from "@/lib/reviews";
import { processed } from "@/lib/records";

export const POST: APIRoute = async ({ request, redirect }) => {
  const form = await request.formData();
  const album = String(form.get("album") ?? "");
  const message = String(form.get("message") ?? "").trim();
  const verdict = form.get("verdict") === "request_changes" ? "request_changes" : "accept";
  const back = String(form.get("back") ?? "/");
  const rec = (await processed()).get(album);
  if (!rec) return new Response("only processed albums can be reviewed", { status: 400 });
  if (verdict === "request_changes" && !message) return new Response("say what should change", { status: 400 });
  const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
  await addReview({ album, at, by: "deity", fingerprint: fingerprint(rec), message, verdict });
  return redirect(`${back.startsWith("/album/") ? back : "/"}#conversation`, 303);
};
