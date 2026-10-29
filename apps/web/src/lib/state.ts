export type State = "triage" | "awaiting agents" | "changes requested" | "blocked" | "accepted";

export const STATES: State[] = ["triage", "awaiting agents", "changes requested", "blocked", "accepted"];

export const GLYPH: Record<State, string> = {
  accepted: "✓",
  blocked: "■",
  "changes requested": "↺",
  "awaiting agents": "◌",
  triage: "·",
};

export const SECTION_ORDER: State[] = ["blocked", "changes requested", "awaiting agents", "accepted", "triage"];

export const SECTION_NOTE: Record<State, string> = {
  blocked: "needs you",
  "changes requested": "back with the agents",
  "awaiting agents": "prepared, no verdict yet",
  accepted: "newest first",
  triage: "not catalogued yet · by folder",
};

export const VERB = {
  accept: "accepted",
  approve: "approved",
  flag: "flagged",
  request_changes: "requested changes",
  note: "note",
} as const;

export type Kind = keyof typeof VERB;

export type Word = { by: string; kind: Kind; at: string; text: string };

export type Item = {
  id: number;
  path: string;
  title: string;
  artist: string;
  artistDir: string;
  state: State;
  by: string | null;
  at: string | null;
  year: number | null;
  dateTag: string;
  codec: string;
  audio: string;
  bytes: number;
  n: number;
  dur: number;
  issues: string[];
  genre: string | null;
  label: string | null;
  original: string | null;
  edition: string | null;
  cover: string | null;
  entries: number;
  word: Word | null;
};
