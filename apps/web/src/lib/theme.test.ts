import { beforeEach, expect, it, vi } from "vitest";
import {
  isTheme,
  THEMES,
  THEME_STORAGE_KEY,
  themeInitializationScript,
} from "@/lib/theme";

beforeEach(() => {
  document.documentElement.dataset.theme = "midnight";
});

function initializeWith(saved: string | null) {
  const getItem = vi.fn(() => saved);
  new Function("localStorage", "document", themeInitializationScript)(
    { getItem },
    document,
  );
  expect(getItem).toHaveBeenCalledWith(THEME_STORAGE_KEY);
}

it.each(THEMES)("restores $label before first paint", ({ id }) => {
  expect(isTheme(id)).toBe(true);
  initializeWith(id);
  expect(document.documentElement).toHaveAttribute("data-theme", id);
});

it.each([null, "", "unexpected-theme"])(
  "keeps Midnight as the default for %s",
  (saved) => {
    expect(isTheme(saved)).toBe(false);
    initializeWith(saved);
    expect(document.documentElement).toHaveAttribute("data-theme", "midnight");
  },
);

it("keeps the default when storage cannot be read", () => {
  const initialize = () =>
    new Function("localStorage", "document", themeInitializationScript)(
      {
        getItem() {
          throw new Error("Storage blocked");
        },
      },
      document,
    );
  expect(initialize).not.toThrow();
  expect(document.documentElement).toHaveAttribute("data-theme", "midnight");
});
