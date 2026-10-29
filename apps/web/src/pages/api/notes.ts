import type { APIRoute } from "astro";

import { addNote } from "@/lib/records";

export const POST: APIRoute = async ({ request, redirect }) => {
  const form = await request.formData();
  const album = String(form.get("album") ?? "");
  const text = String(form.get("text") ?? "").trim();
  const kind = form.get("kind") === "instruction" ? "instruction" : "note";
  const back = String(form.get("back") ?? "/");
  if (!(album && text)) return new Response("album and text are required", { status: 400 });
  const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
  await addNote({ album, at, by: "theo", kind, text });
  return redirect(`${back.startsWith("/album/") ? back : "/"}#notes`, 303);
};
