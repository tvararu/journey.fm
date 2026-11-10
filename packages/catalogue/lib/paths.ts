import { resolve } from "node:path";

export const ROOT = resolve(process.env["JOURNEY_ROOT"] ?? `${import.meta.dir}/../../..`);
export const META = resolve(process.env["JOURNEY_DATA"] ?? `${ROOT}/data`);
export const INV = `${META}/inventory`;
export const CATALOGUE = `${META}/catalogue`;
export const RAW = `${META}/raw`;
export const PREVIEWS = `${META}/previews`;
export const RECORDS = `${ROOT}/records`;
export const SCRIPTS = `${ROOT}/packages/catalogue`;
export const TAGGING = `${ROOT}/tools/tagging`;

function need(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`${name} is not set; see mise.example.toml`);
  return v.replace(/\/+$/, "");
}

export const host = {
  get ssh() {
    return need("JOURNEY_HOST");
  },
  get library() {
    return need("JOURNEY_LIBRARY");
  },
  get meta() {
    return need("JOURNEY_META");
  },
  get bun() {
    return process.env["JOURNEY_HOST_BUN"] || "bun";
  },
};
