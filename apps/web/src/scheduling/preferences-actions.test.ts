import { beforeEach, describe, expect, it, vi } from "vitest";
import { ForbiddenError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";

const mocks = vi.hoisted(() => ({
  auth: vi.fn(),
  config: vi.fn(),
  client: vi.fn(),
  unsafe: vi.fn(),
  revalidate: vi.fn(),
}));
vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidate }));
vi.mock("@/auth/authorization.server", () => ({
  requireAuthorizedUser: mocks.auth,
}));
vi.mock("@/config/preferences-server", () => ({
  getPreferencesConfiguration: mocks.config,
}));
vi.mock("@/lib/database/server-data", () => ({
  getServerPreferencesClient: mocks.client,
}));
import { savePostingPreferences } from "@/scheduling/preferences-actions";

function form() {
  const value = new FormData();
  Object.entries({
    tiktok_weekly: "14",
    tiktok_ceiling: "3",
    youtube_weekly: "14",
    youtube_ceiling: "3",
    enabled: "true",
    confirm: "on",
    actor: "spoof@example.invalid",
  }).forEach(([key, data]) => value.set(key, data));
  return value;
}
const idle = { status: "idle", message: "" } as const;
describe("saving scheduling preferences", () => {
  beforeEach(() => {
    vi.resetAllMocks();
    mocks.auth.mockResolvedValue({ email: "operator@example.invalid" });
    mocks.unsafe.mockResolvedValue([{ revision: 2 }]);
    mocks.client.mockReturnValue({ unsafe: mocks.unsafe });
  });
  it("uses the narrow parameterized save and derives the actor from the session", async () => {
    expect(await savePostingPreferences(1, idle, form())).toMatchObject({
      status: "success",
      revision: 2,
      saved: {
        enabled: true,
        tiktok_weekly: 14,
        tiktok_ceiling: 3,
        youtube_weekly: 14,
        youtube_ceiling: 3,
      },
    });
    expect(mocks.unsafe).toHaveBeenCalledWith(
      expect.stringContaining("public.save_scheduling_preferences"),
      [1, 14, 3, 14, 3, true, "operator@example.invalid"],
      { prepare: false },
    );
    expect(mocks.revalidate).toHaveBeenCalledWith("/scheduling-preferences");
  });
  it("returns only normalized values after a confirmed OFF save", async () => {
    const data = form();
    data.set("enabled", "false");
    data.set("tiktok_weekly", "020");
    const result = await savePostingPreferences(1, idle, data);
    expect(result).toMatchObject({
      status: "success",
      saved: { enabled: false, tiktok_weekly: 20 },
    });
    expect(result).not.toHaveProperty("actor");
    expect(result).not.toHaveProperty("saved.actor");
  });
  it("does not return confirmed values for an unexpected database revision", async () => {
    mocks.unsafe.mockResolvedValue([{ revision: 3 }]);
    const result = await savePostingPreferences(1, idle, form());
    expect(result).toMatchObject({ status: "error" });
    expect(result).not.toHaveProperty("saved");
    expect(mocks.revalidate).not.toHaveBeenCalled();
  });
  it.each([
    ["confirm", ""],
    ["tiktok_weekly", "6"],
    ["tiktok_weekly", "22"],
    ["tiktok_weekly", "14.5"],
    ["enabled", "on"],
  ])("rejects invalid %s=%s before connecting", async (field, value) => {
    const data = form();
    data.set(field, value);
    expect(await savePostingPreferences(1, idle, data)).toMatchObject({
      status: "error",
    });
    expect(mocks.client).not.toHaveBeenCalled();
  });
  it("does not connect after an authorization failure", async () => {
    mocks.auth.mockRejectedValue(new ForbiddenError());
    expect(await savePostingPreferences(1, idle, form())).toMatchObject({
      status: "error",
    });
    expect(mocks.client).not.toHaveBeenCalled();
  });
  it("does not connect if staging credentials are absent", async () => {
    mocks.config.mockImplementation(() => {
      throw new ConfigurationError("missing");
    });
    expect(await savePostingPreferences(1, idle, form())).toMatchObject({
      status: "error",
    });
    expect(mocks.client).not.toHaveBeenCalled();
  });
  it.each([
    ["P4101", "changed"],
    ["P4102", "Resolve pending"],
    ["08006", "could not be confirmed"],
  ])("handles %s without leaking raw errors", async (code, message) => {
    mocks.unsafe.mockRejectedValue({
      code,
      message: "PRIVATE_DATABASE_DETAILS",
    });
    const result = await savePostingPreferences(1, idle, form());
    expect(result.message).toContain(message);
    expect(result.message).not.toContain("PRIVATE_DATABASE_DETAILS");
    expect(mocks.revalidate).not.toHaveBeenCalled();
  });
});
