import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { ThemeSelector } from "@/components/shell/theme-selector";
import { THEMES, THEME_STORAGE_KEY } from "@/lib/theme";

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
  await userEvent.setup().click(screen.getByRole("button", { name: "Dark" }));
  expect(document.documentElement).toHaveAttribute("data-theme", "dark");
  expect(screen.getByRole("button", { name: "Dark" })).toHaveAttribute(
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
      newValue: "dark",
    }),
  );
  expect(screen.getByLabelText("Color theme")).toHaveValue("dark");
  fireEvent(
    window,
    new StorageEvent("storage", {
      key: THEME_STORAGE_KEY,
      newValue: "unexpected-theme",
    }),
  );
  expect(screen.getByLabelText("Color theme")).toHaveValue("midnight");
});

it.each(THEMES)(
  "offers $label on desktop and mobile",
  async ({ id, label }) => {
    const user = userEvent.setup();
    render(
      <>
        <ThemeSelector />
        <ThemeSelector compact />
      </>,
    );
    expect(screen.getAllByRole("button")).toHaveLength(4);
    expect(screen.getAllByRole("option")).toHaveLength(4);
    await user.click(screen.getByRole("button", { name: label }));
    expect(screen.getByLabelText("Color theme")).toHaveValue(id);
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe(id);

    await user.selectOptions(screen.getByLabelText("Color theme"), "forest");
    await user.selectOptions(screen.getByLabelText("Color theme"), id);
    expect(document.documentElement).toHaveAttribute("data-theme", id);
    expect(localStorage.getItem(THEME_STORAGE_KEY)).toBe(id);
    for (const item of THEMES) {
      expect(screen.getByRole("button", { name: item.label })).toHaveAttribute(
        "aria-pressed",
        String(item.id === id),
      );
    }
  },
);
