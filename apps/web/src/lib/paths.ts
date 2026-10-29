/* eslint-disable n/no-process-env -- the one module that reads CATALOGUE_DATA */
export const DATA = process.env["CATALOGUE_DATA"] ?? `${process.cwd()}/../data`;
export const INVENTORY = `${DATA}/inventory`;
export const CATALOGUE = `${DATA}/catalogue`;
export const NOTES = `${DATA}/../notes.jsonl`;
export const REVIEWS = `${DATA}/../reviews.jsonl`;
export const VERDICTS = `${DATA}/../verdicts.jsonl`;
export const COMFY = process.env["COMFY_URL"] ?? "https://t1.example.ts.net:8188";
export const ROOT = `${DATA}/..`;
