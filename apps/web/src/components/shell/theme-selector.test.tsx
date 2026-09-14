import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ThemeSelector } from "@/components/shell/theme-selector";
import { THEME_STORAGE_KEY } from "@/lib/theme";

beforeEach(() => {
  document.documentElement.dataset.theme = "midnight";
  localStorage.clear();
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

it("keeps desktop and mobile controls in sync and remembers a theme", async () => {
  const user = userEvent.setup();
  render(
    <>
      <ThemeSelector />
      <ThemeSelector compact />
    </>,
  );
  await user.click(screen.getByRole("button", { name: "Daylight" }));
  expect(document.documentElement).toHaveAttribute("data-theme", "daylight");
  expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("daylight");
  expect(screen.getByLabelText("Color theme")).toHaveValue("daylight");
  await user.selectOptions(screen.getByLabelText("Color theme"), "forest");
  expect(screen.getByRole("button", { name: "Forest" })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
  expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe("forest");
});

it("can still switch themes when browser storage is blocked", async () => {
  vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
    throw new Error("Unavailable");
  });
  render(<ThemeSelector />);
  await userEvent.setup().click(screen.getByRole("button", { name: "Forest" }));
  expect(document.documentElement).toHaveAttribute("data-theme", "forest");
  expect(screen.getByRole("button", { name: "Forest" })).toHaveAttribute(
    "aria-pressed",
    "true",
  );
});

it("syncs another tab's preference and rejects invalid stored themes", () => {
  render(<ThemeSelector compact />);
  fireEvent(
    window,
    new StorageEvent("storage", {
      key: THEME_STORAGE_KEY,
      newValue: "daylight",
    }),
  );
  expect(screen.getByLabelText("Color theme")).toHaveValue("daylight");
  fireEvent(
    window,
    new StorageEvent("storage", {
      key: THEME_STORAGE_KEY,
      newValue: "unexpected-theme",
    }),
  );
  expect(screen.getByLabelText("Color theme")).toHaveValue("midnight");
});
