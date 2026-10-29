import { basename } from "node:path";

import { COMFY, DATA } from "./paths";
import type { CoverCandidate } from "./records";

export const UPSCALERS = {
  "seedvr2-3b": { label: "SeedVR2 3B", model: "seedvr2_3b_fp16.safetensors", kind: "seedvr2" },
  "ultrasharpv2": { label: "4x-UltraSharpV2", model: "4x-UltraSharpV2.safetensors", kind: "esrgan" },
  "seedvr2-7b-sharp": { label: "SeedVR2 7B sharp", model: "seedvr2_7b_sharp_fp16.safetensors", kind: "seedvr2" },
} as const;

export type Upscaler = keyof typeof UPSCALERS;

const TARGET = 3000;
type Graph = Record<string, { class_type: string; inputs: Record<string, unknown> }>;

function target(w: number, h: number): [number, number] {
  const k = TARGET / Math.max(w, h);
  return [Math.round(w * k), Math.round(h * k)];
}

function esrgan(image: string, model: string, size: [number, number]): Graph {
  return {
    "1": { class_type: "LoadImage", inputs: { image } },
    "2": { class_type: "UpscaleModelLoader", inputs: { model_name: model } },
    "3": { class_type: "ImageUpscaleWithModel", inputs: { image: ["1", 0], upscale_model: ["2", 0] } },
    "4": { class_type: "ImageScale", inputs: { crop: "disabled", height: size[1], image: ["3", 0], upscale_method: "lanczos", width: size[0] } },
    "5": { class_type: "SaveImage", inputs: { filename_prefix: "catalogue-upscale", images: ["4", 0] } },
  };
}

function seedvr2(image: string, model: string, size: [number, number]): Graph {
  const tiles = { overlap: 128, temporal_overlap: 8, temporal_size: 64, tile_size: 512 };
  return {
    "1": { class_type: "LoadImage", inputs: { image } },
    "2": { class_type: "ImageScale", inputs: { crop: "disabled", height: size[1], image: ["1", 0], upscale_method: "lanczos", width: size[0] } },
    "3": { class_type: "SeedVR2Preprocess", inputs: { resized_images: ["2", 0] } },
    "4": { class_type: "VAELoader", inputs: { vae_name: "seedvr2_ema_vae_fp16.safetensors" } },
    "5": { class_type: "VAEEncodeTiled", inputs: { ...tiles, pixels: ["3", 0], vae: ["4", 0] } },
    "6": { class_type: "UNETLoader", inputs: { unet_name: model, weight_dtype: "default" } },
    "7": { class_type: "SeedVR2Conditioning", inputs: { model: ["6", 0], vae_conditioning: ["5", 0] } },
    "8": {
      class_type: "KSampler",
      inputs: {
        cfg: 1, denoise: 1, latent_image: ["5", 0], model: ["6", 0], negative: ["7", 1], positive: ["7", 0],
        sampler_name: "euler", scheduler: "simple", seed: 1, steps: 1,
      },
    },
    "9": { class_type: "VAEDecodeTiled", inputs: { ...tiles, samples: ["8", 0], vae: ["4", 0] } },
    "10": { class_type: "SeedVR2PostProcessing", inputs: { color_correction_method: "lab", images: ["9", 0], original_resized_images: ["2", 0] } },
    "11": { class_type: "SaveImage", inputs: { filename_prefix: "catalogue-upscale", images: ["10", 0] } },
  };
}

async function upload(path: string): Promise<string> {
  const form = new FormData();
  form.append("image", Bun.file(path), basename(path));
  form.append("overwrite", "true");
  const res = await fetch(`${COMFY}/upload/image`, { body: form, method: "POST" });
  return ((await res.json()) as { name: string }).name;
}

type History = {
  status?: { status_str?: string; completed?: boolean; messages?: [string, unknown][] };
  outputs?: Record<string, { images?: { filename: string; subfolder: string; type: string }[] }>;
};

async function waitFor(id: string): Promise<History> {
  for (;;) {
    await Bun.sleep(2000);
    const h = ((await (await fetch(`${COMFY}/history/${id}`)).json()) as Record<string, History>)[id];
    if (h?.status?.status_str === "error") throw new Error(JSON.stringify(h.status.messages).slice(0, 500));
    if (h?.status?.completed) return h;
  }
}

export async function upscale(slug: string, c: CoverCandidate, which: Upscaler): Promise<CoverCandidate> {
  const u = UPSCALERS[which];
  const size = target(c.width, c.height);
  const image = await upload(`${DATA}/${c.path}`);
  const graph = u.kind === "esrgan" ? esrgan(image, u.model, size) : seedvr2(image, u.model, size);
  const queued = await fetch(`${COMFY}/prompt`, { body: JSON.stringify({ client_id: "catalogue", prompt: graph }), method: "POST" });
  const { prompt_id: id } = (await queued.json()) as { prompt_id: string };
  const out = Object.values((await waitFor(id)).outputs ?? {}).flatMap((o) => o.images ?? [])[0];
  if (!out) throw new Error("ComfyUI returned no image");
  const view = new URLSearchParams({ filename: out.filename, subfolder: out.subfolder, type: out.type });
  const bytes = new Uint8Array(await (await fetch(`${COMFY}/view?${view}`)).arrayBuffer());
  const name = `upscaled-${which}-${basename(c.path).replace(/\.[^.]+$/, "")}.png`;
  const rel = `raw/${slug}/covers/${name}`;
  await Bun.write(`${DATA}/${rel}`, bytes);
  return {
    bytes: bytes.length,
    height: size[1],
    id: `Upscaled (${which}):${name}`,
    note: `${c.source} ${c.width}x${c.height} upscaled with ${u.label}`,
    path: rel,
    source: `Upscaled (${which})`,
    types: c.types,
    width: size[0],
  };
}
