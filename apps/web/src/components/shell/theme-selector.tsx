"use client";

import { useSyncExternalStore } from "react";
import { isTheme, THEMES, THEME_STORAGE_KEY, type Theme } from "@/lib/theme";

const CHANGE_EVENT = "creator-analytics-theme-change";

function currentTheme(): Theme {
  const value = document.documentElement.dataset.theme;
  return isTheme(value) ? value : "midnight";
}

function subscribe(notify: () => void) {
  function syncStorage(event: StorageEvent) {
    if (event.key !== THEME_STORAGE_KEY && event.key !== null) return;
    document.documentElement.dataset.theme = isTheme(event.newValue)
      ? event.newValue
      : "midnight";
    notify();
  }
  window.addEventListener(CHANGE_EVENT, notify);
  window.addEventListener("storage", syncStorage);
  return () => {
    window.removeEventListener(CHANGE_EVENT, notify);
    window.removeEventListener("storage", syncStorage);
  };
}

export function ThemeSelector({ compact = false }: { compact?: boolean }) {
  const theme = useSyncExternalStore(subscribe, currentTheme, () => "midnight");
  function changeTheme(next: Theme) {
    document.documentElement.setAttribute("data-theme", next);
    try {
      localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      // Appearance still changes when browser storage is unavailable.
    }
    window.dispatchEvent(new Event(CHANGE_EVENT));
  }
  if (compact) {
    return (
      <label className="text-muted text-xs">
        <span className="sr-only">Color theme</span>
        <select
          className="border-line bg-surface text-foreground max-w-28 rounded-lg border px-2 py-2 text-xs"
          value={theme}
          onChange={(event) => {
            if (isTheme(event.target.value)) changeTheme(event.target.value);
          }}
        >
          {THEMES.map((item) => (
            <option key={item.id} value={item.id}>
              {item.label}
            </option>
          ))}
        </select>
      </label>
    );
  }
  return (
    <fieldset>
      <legend className="text-muted mb-3 text-xs font-medium">
        Appearance
      </legend>
      <div className="grid grid-cols-3 gap-2">
        {THEMES.map((item) => (
          <button
            aria-pressed={theme === item.id}
            className="theme-choice"
            key={item.id}
            onClick={() => changeTheme(item.id)}
            type="button"
          >
            <span aria-hidden className="theme-swatch" data-swatch={item.id} />
            {item.label}
          </button>
        ))}
      </div>
    </fieldset>
  );
}
