import { afterEach, beforeEach, expect, it, vi } from "vitest";
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { SavedPreference } from "@/scheduling/preferences";
vi.mock("@/scheduling/preferences-actions", () => ({
  savePostingPreferences: vi.fn(),
}));
import { PostingPreferencesForm } from "@/components/preferences/posting-preferences-form";
import { savePostingPreferences } from "@/scheduling/preferences-actions";
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
beforeEach(() => vi.resetAllMocks());
it("identifies production and locks activation during the OFF rollout", () => {
  render(
    <PostingPreferencesForm
      settings={settings}
      coverage={[]}
      environment="production"
      activationAllowed={false}
    />,
  );
  expect(screen.getByText(/Production ·/)).toHaveTextContent("Rules off");
  expect(screen.queryByText(/Staging only/)).not.toBeInTheDocument();
  expect(
    screen.getByRole("combobox", { name: "Use the new rules in production" }),
  ).toHaveValue("false");
  expect(
    screen.getByRole("option", {
      name: "On — use for new production proposals",
    }),
  ).toBeDisabled();
  expect(
    screen.getByRole("button", { name: "Save production preferences" }),
  ).toBeInTheDocument();
  expect(screen.getByText(/Activation is locked/)).toBeInTheDocument();
});
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

it.each([false, true])(
  "keeps the confirmed values visible after saving from enabled=%s",
  async (enabled) => {
    const user = userEvent.setup();
    const saved = {
      enabled: !enabled,
      tiktok_weekly: 20,
      tiktok_ceiling: 4,
      youtube_weekly: 21,
      youtube_ceiling: 3,
    };
    vi.mocked(savePostingPreferences).mockResolvedValue({
      status: "success",
      revision: 2,
      saved,
      message: "Saved in staging. No posts were moved.",
    });
    const { rerender } = render(
      <PostingPreferencesForm
        settings={settings.map((setting) => ({ ...setting, enabled }))}
        coverage={[]}
      />,
    );
    const toggle = screen.getByRole("combobox", {
      name: "Use the new rules in staging",
    });
    await user.selectOptions(toggle, String(!enabled));
    await user.clear(screen.getByLabelText("TikTok weekly target"));
    await user.type(screen.getByLabelText("TikTok weekly target"), "20");
    await user.clear(screen.getByLabelText("TikTok daily ceiling"));
    await user.type(screen.getByLabelText("TikTok daily ceiling"), "4");
    await user.clear(screen.getByLabelText("YouTube Shorts weekly target"));
    await user.type(
      screen.getByLabelText("YouTube Shorts weekly target"),
      "21",
    );
    expect(screen.getByText(/Staging only/)).toHaveTextContent(
      enabled ? "Rules on" : "Rules off",
    );
    await user.click(screen.getByRole("checkbox"));
    await user.click(
      screen.getByRole("button", { name: "Save staging preferences" }),
    );
    expect(await screen.findByRole("status")).toHaveTextContent(
      "Saved in staging",
    );
    expect(toggle).toHaveValue(String(!enabled));
    expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(20);
    expect(screen.getByLabelText("TikTok daily ceiling")).toHaveValue(4);
    expect(screen.getByLabelText("YouTube Shorts weekly target")).toHaveValue(
      21,
    );
    expect(screen.getByText(/Staging only/)).toHaveTextContent(
      !enabled ? "Rules on" : "Rules off",
    );
    expect(toggle).toBeDisabled();
    expect(screen.getByRole("checkbox")).not.toBeChecked();
    expect(
      screen.getByRole("button", { name: "Save staging preferences" }),
    ).toBeDisabled();
    expect(
      screen.getByRole("link", { name: "Reload saved settings" }),
    ).toHaveAttribute("href", "/scheduling-preferences");
    const submitted = vi.mocked(savePostingPreferences).mock.calls[0][2];
    expect(Object.fromEntries(submitted)).toMatchObject({
      enabled: String(!enabled),
      tiktok_weekly: "20",
      tiktok_ceiling: "4",
      youtube_weekly: "21",
      youtube_ceiling: "3",
      confirm: "on",
    });
    // A late server render must not reset the just-confirmed display.
    rerender(<PostingPreferencesForm settings={settings} coverage={[]} />);
    expect(toggle).toHaveValue(String(!enabled));
    expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(20);
  },
);

it("keeps the draft on error and binds it to the revision originally reviewed", async () => {
  const user = userEvent.setup();
  vi.mocked(savePostingPreferences).mockResolvedValue({
    status: "error",
    message:
      "These settings changed. Reload the page and review them before saving.",
  });
  const { rerender } = render(
    <PostingPreferencesForm settings={settings} coverage={[]} />,
  );
  await user.selectOptions(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
    "true",
  );
  await user.clear(screen.getByLabelText("TikTok weekly target"));
  await user.type(screen.getByLabelText("TikTok weekly target"), "7");
  rerender(
    <PostingPreferencesForm
      settings={settings.map((s) => ({ ...s, revision: 2 }))}
      coverage={[]}
    />,
  );
  await user.click(screen.getByRole("checkbox"));
  await user.click(
    screen.getByRole("button", { name: "Save staging preferences" }),
  );
  expect(await screen.findByRole("alert")).toHaveTextContent("Reload the page");
  expect(vi.mocked(savePostingPreferences).mock.calls[0][0]).toBe(1);
  expect(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
  ).toHaveValue("true");
  expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(7);
  expect(screen.getByText(/Staging only/)).toHaveTextContent("Rules off");
  expect(screen.getByRole("checkbox")).not.toBeChecked();
  expect(
    screen.getByRole("button", { name: "Save staging preferences" }),
  ).not.toBeDisabled();
});

it("disables editing while a save is pending without resetting the draft", async () => {
  const user = userEvent.setup();
  let finish!: (
    state: Awaited<ReturnType<typeof savePostingPreferences>>,
  ) => void;
  vi.mocked(savePostingPreferences).mockImplementation(
    () =>
      new Promise((resolve) => {
        finish = resolve;
      }),
  );
  render(<PostingPreferencesForm settings={settings} coverage={[]} />);
  await user.selectOptions(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
    "true",
  );
  await user.click(screen.getByRole("checkbox"));
  await user.click(
    screen.getByRole("button", { name: "Save staging preferences" }),
  );
  expect(await screen.findByRole("button", { name: "Saving…" })).toBeDisabled();
  expect(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
  ).toBeDisabled();
  expect(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
  ).toHaveValue("true");
  await act(async () =>
    finish({ status: "error", message: "The save could not be confirmed." }),
  );
  expect(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
  ).toHaveValue("true");
});

it("requires a fresh review before submitting", async () => {
  const user = userEvent.setup();
  render(<PostingPreferencesForm settings={settings} coverage={[]} />);
  await user.click(
    screen.getByRole("button", { name: "Save staging preferences" }),
  );
  expect(savePostingPreferences).not.toHaveBeenCalled();
});

it("loads the persisted values and revision on a fresh page", async () => {
  const user = userEvent.setup();
  vi.mocked(savePostingPreferences).mockResolvedValue({
    status: "error",
    message: "Test save was not applied.",
  });
  render(
    <PostingPreferencesForm
      settings={settings.map((setting) => ({
        ...setting,
        revision: 2,
        enabled: true,
        posts_per_week: 21,
      }))}
      coverage={[]}
    />,
  );
  expect(screen.getByText(/Staging only/)).toHaveTextContent("Rules on");
  expect(screen.getByLabelText("TikTok weekly target")).toHaveValue(21);
  expect(screen.getByRole("checkbox")).not.toBeChecked();
  await user.selectOptions(
    screen.getByRole("combobox", { name: "Use the new rules in staging" }),
    "false",
  );
  await user.click(screen.getByRole("checkbox"));
  await user.click(
    screen.getByRole("button", { name: "Save staging preferences" }),
  );
  await screen.findByRole("alert");
  expect(vi.mocked(savePostingPreferences).mock.calls[0][0]).toBe(2);
  expect(
    vi.mocked(savePostingPreferences).mock.calls[0][2].get("enabled"),
  ).toBe("false");
});
