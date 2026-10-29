/* eslint-disable n/no-process-env -- the one module that reads CATALOGUE_DATA */
export const DATA = process.env["CATALOGUE_DATA"] ?? `${process.cwd()}/../data`;
export const INVENTORY = `${DATA}/inventory`;
export const CATALOGUE = `${DATA}/catalogue`;
export const NOTES = `${DATA}/../notes.jsonl`;
