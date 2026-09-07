export const THEMES = [
  { id: "midnight", label: "Midnight" },
  { id: "daylight", label: "Daylight" },
  { id: "forest", label: "Forest" },
] as const;

export type Theme = (typeof THEMES)[number]["id"];
export const THEME_STORAGE_KEY = "creator-analytics-theme";

export function isTheme(value: unknown): value is Theme {
  return THEMES.some((theme) => theme.id === value);
}

// Only a validated appearance preference is read, before first paint.
export const themeInitializationScript = `(() => {
  try {
    const saved = localStorage.getItem("${THEME_STORAGE_KEY}");
    if (${JSON.stringify(THEMES.map((theme) => theme.id))}.includes(saved)) {
      document.documentElement.dataset.theme = saved;
    }
  } catch {}
})();`;
