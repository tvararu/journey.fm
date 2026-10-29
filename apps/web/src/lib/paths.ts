/* eslint-disable n/no-process-env -- the one module that reads the environment */
export const ROOT = process.env["JOURNEY_ROOT"] ?? `${process.cwd()}/../..`;
export const DATA = process.env["JOURNEY_DATA"] ?? `${ROOT}/data`;
export const INVENTORY = `${DATA}/inventory`;
export const CATALOGUE = `${DATA}/catalogue`;
export const NOTES = `${ROOT}/records/notes.jsonl`;
export const REVIEWS = `${ROOT}/records/reviews.jsonl`;
export const VERDICTS = `${ROOT}/records/verdicts.jsonl`;
export const SCRIPTS = `${ROOT}/packages/catalogue`;
export const COMFY = process.env["COMFY_URL"] ?? "http://127.0.0.1:8188";
