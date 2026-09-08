import { afterEach, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { SavedPreference } from "@/scheduling/preferences";
vi.mock("@/scheduling/preferences-actions", () => ({
  savePostingPreferences: vi.fn(),
}));
import { PostingPreferencesForm } from "@/components/preferences/posting-preferences-form";
const settings: SavedPreference[] = (["tiktok", "youtube"] as const).map(
  (platform) => ({
    platform,
    posts_per_week: 14,
    max_posts_per_day: 3,
    min_gap_hours: 6,
    protected_hours: 24,
    timezone_name: "America/Denver",
    revision: 1,
    enabled: false,
    daily_floor: 1,
    max_shift_hours: 12,
    allowed_hours: "all",
  }),
);
afterEach(cleanup);
it("separates staging settings, unsaved changes, and observed coverage", () => {
  render(
    <PostingPreferencesForm
      settings={settings}
      coverage={[
        {
          buffer_channel_id: "test-channel",
          platform: "tiktok",
          timezone_name: "America/Denver",
          local_date: "2026-09-14",
          scheduled_count: 0,
          planned_count: 0,
          coverage_note: "No eligible clip within 12 hours.",
        },
      ]}
    />,
  );
  expect(screen.getByText(/Staging only/)).toHaveTextContent("Rules off");
  expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(14);
  expect(screen.getByRole("checkbox")).toBeRequired();
  expect(screen.getByRole("checkbox")).not.toBeChecked();
  expect(screen.getByText("Gap to fill")).toBeInTheDocument();
  expect(
    screen.getByText(/This table does not preview unsaved edits/),
  ).toBeInTheDocument();
  expect(
    screen.getByText(/12 elapsed hours before or after/),
  ).toBeInTheDocument();
  expect(
    screen.queryByRole("button", { name: /approve|apply|refresh/i }),
  ).not.toBeInTheDocument();
  fireEvent.change(screen.getByLabelText("TikTok weekly target"), {
    target: { value: "7" },
  });
  expect(screen.getByLabelText("YouTube Shorts weekly target")).toHaveValue(14);
});
