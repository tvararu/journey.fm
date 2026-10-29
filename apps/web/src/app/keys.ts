export function typing(e: KeyboardEvent): boolean {
  if (e.metaKey || e.ctrlKey || e.altKey) return true;
  const t = e.target;
  if (!(t instanceof HTMLElement)) return false;
  return t.matches("input, textarea, select") || t.isContentEditable;
}

const PAGES: Record<string, string> = { "1": "/", "2": "/review", "3": "/artists" };

document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
    e.preventDefault();
    document.dispatchEvent(new CustomEvent("palette:open"));
    return;
  }
  if (e.key === "Escape") {
    if (!document.querySelector("dialog[open]")) (document.activeElement as HTMLElement | null)?.blur();
    return;
  }
  if (typing(e) || document.querySelector("dialog[open]")) return;
  const page = PAGES[e.key];
  if (page) {
    location.href = page;
    return;
  }
  if (e.key === "/") {
    const el = document.querySelector<HTMLElement>("[data-search]");
    if (el) {
      e.preventDefault();
      el.focus();
    }
  }
});
