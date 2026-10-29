import type { APIRoute } from "astro";

import { fingerprint, record } from "@/lib/approvals";
import { processed } from "@/lib/records";

export const POST: APIRoute = async ({ request, redirect }) => {
  const form = await request.formData();
  const album = String(form.get("album") ?? "");
  const action = form.get("action") === "revoke" ? "revoke" : "approve";
  const back = String(form.get("back") ?? "/");
  const rec = (await processed()).get(album);
  if (!rec) return new Response("only processed albums can be approved", { status: 400 });
  const at = new Date().toLocaleString("sv-SE", { timeZone: "Europe/London" }).slice(0, 16);
  await record({ action, album, at, by: "deity", fingerprint: fingerprint(rec) });
  return redirect(`${back.startsWith("/album/") ? back : "/"}#proposed`, 303);
};
