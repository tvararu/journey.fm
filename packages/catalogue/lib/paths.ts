import { resolve } from "node:path";

export const META = resolve(process.env["JOURNEY_DATA"] ?? `${import.meta.dir}/../../data`);
export const INV = `${META}/inventory`;
export const CATALOGUE = `${META}/catalogue`;
export const RAW = `${META}/raw`;
