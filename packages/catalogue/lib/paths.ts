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
export const ORCA = process.env["ORCA_CLI_COMMAND"] ?? (process.platform === "linux" ? "orca-ide" : "orca");
