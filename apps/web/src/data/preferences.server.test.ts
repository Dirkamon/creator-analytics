import { beforeEach, describe, expect, it, vi } from "vitest";
import { ForbiddenError } from "@/auth/errors";
const mocks = vi.hoisted(() => ({ auth: vi.fn(), config: vi.fn() }));
vi.mock("@/auth/authorization.server", () => ({
  requireAuthorizedUser: mocks.auth,
}));
vi.mock("@/config/preferences-server", () => ({
  getPreferencesConfiguration: mocks.config,
}));
vi.mock("@/data/read-only.server", () => ({
  serverReadOnlyReader: { select: vi.fn() },
}));
import { loadSchedulingPreferences } from "@/data/preferences.server";
import { compileSelectSpecification } from "@/data/database-query";

const settings = ["tiktok", "youtube"].map((platform) => ({
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
}));
const coverage = [
  {
    buffer_channel_id: "test-channel",
    platform: "tiktok",
    timezone_name: "America/Denver",
    local_date: "2026-09-14",
    scheduled_count: 0,
    planned_count: 0,
    coverage_note: "No eligible post",
  },
];
describe("saved preference reads", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.auth.mockResolvedValue({ email: "test@example.invalid" });
    mocks.config.mockReturnValue({
      environment: "production",
      activationAllowed: false,
    });
  });
  it("authorizes and reads only explicit reporting-view columns", async () => {
    const select = vi.fn(async (query) => {
      expect(compileSelectSpecification(query).text).toContain(
        'from "creator_app".',
      );
      expect(query.columns).not.toContain("*");
      return query.relation === "scheduling_preferences" ? settings : coverage;
    });
    expect(await loadSchedulingPreferences({ select })).toMatchObject({
      settings,
      coverage,
      environment: "production",
      activationAllowed: false,
    });
    expect(mocks.auth).toHaveBeenCalledOnce();
  });
  it("blocks unauthorized reads", async () => {
    const select = vi.fn();
    mocks.auth.mockRejectedValue(new ForbiddenError());
    await expect(loadSchedulingPreferences({ select })).rejects.toThrow();
    expect(select).not.toHaveBeenCalled();
  });
  it.each([
    { rows: [] },
    { rows: [settings[0]] },
    { rows: [settings[0], settings[0]] },
    { rows: [settings[0], { ...settings[1], revision: 2 }] },
  ])("rejects missing or inconsistent settings", async ({ rows }) => {
    await expect(
      loadSchedulingPreferences({
        select: vi.fn(async (query) =>
          query.relation === "scheduling_preferences" ? rows : coverage,
        ),
      }),
    ).rejects.toThrow();
  });
  it("does not report a failed or truncated read as an empty queue", async () => {
    await expect(
      loadSchedulingPreferences({
        select: vi.fn().mockRejectedValue(new Error("unavailable")),
      }),
    ).rejects.toThrow();
    await expect(
      loadSchedulingPreferences({
        select: vi.fn(async (query) =>
          query.relation === "scheduling_preferences"
            ? settings
            : Array(500).fill(coverage[0]),
        ),
      }),
    ).rejects.toThrow();
  });
});
