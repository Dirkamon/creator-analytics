import { beforeEach, describe, expect, it, vi } from "vitest";

import { ForbiddenError } from "@/auth/errors";
import { initialLabelingActionState } from "@/labeling/state";

const mocks = vi.hoisted(() => ({
  requireAuthorizedUser: vi.fn(),
  getServerEnvironment: vi.fn(),
  getServerLabelingClient: vi.fn(),
  revalidatePath: vi.fn(),
  begin: vi.fn(),
  unsafe: vi.fn(),
}));

vi.mock("next/cache", () => ({ revalidatePath: mocks.revalidatePath }));
vi.mock("@/auth/authorization.server", () => ({
  requireAuthorizedUser: mocks.requireAuthorizedUser,
}));
vi.mock("@/config/env-server", () => ({
  getServerEnvironment: mocks.getServerEnvironment,
}));
vi.mock("@/lib/database/server-data", () => ({
  getServerLabelingClient: mocks.getServerLabelingClient,
}));

import { saveContentLabel } from "@/labeling/actions";

function createLabelForm() {
  const formData = new FormData();
  formData.set("mode", "create");
  formData.set("post_id", "SANITIZED_POST");
  formData.set("clip_group", "Sanitized Clip Group");
  formData.set("game", "Arc Raiders");
  formData.set("content_type", "Funny moment");
  formData.set("vibe", "Chaotic");
  formData.set("hook_type", "Immediate action");
  formData.set("duration_seconds", "45");
  formData.set("editing_intensity", "Medium");
  formData.set("source_recording", "sanitized-project");
  formData.set("notes", "Sanitized note");
  return formData;
}

describe("controlled labeling action", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.requireAuthorizedUser.mockResolvedValue({
      id: "SANITIZED_USER",
      email: "operator@example.invalid",
    });
    mocks.getServerEnvironment.mockReturnValue({
      CREATOR_ANALYTICS_LABELING_ENABLED: true,
    });
    mocks.unsafe.mockResolvedValue([
      {
        result_content_item_id: "00000000-0000-0000-0000-000000000001",
        result_clip_group: "sanitized clip group",
        affected_post_count: 1,
      },
    ]);
    mocks.begin.mockImplementation(
      async (
        callback: (transaction: { unsafe: typeof mocks.unsafe }) => unknown,
      ) => callback({ unsafe: mocks.unsafe }),
    );
    mocks.getServerLabelingClient.mockReturnValue({ begin: mocks.begin });
  });

  it("authorizes, validates, and calls only the controlled database wrapper", async () => {
    await expect(
      saveContentLabel(initialLabelingActionState, createLabelForm()),
    ).resolves.toEqual({
      status: "success",
      message: "Label saved. The post is now linked to its new Clip Group.",
    });

    expect(mocks.requireAuthorizedUser).toHaveBeenCalledOnce();
    expect(mocks.unsafe).toHaveBeenCalledWith(
      expect.stringContaining("process_content_label_payload_for_web"),
      [
        expect.objectContaining({ post_id: "SANITIZED_POST" }),
        "operator@example.invalid",
        "create",
        false,
      ],
      { prepare: false },
    );
    expect(mocks.revalidatePath).toHaveBeenCalledWith("/label-queue");
    expect(mocks.revalidatePath).toHaveBeenCalledWith("/dashboard");
  });

  it("requires shared-effect confirmation before linking an existing group", async () => {
    const formData = new FormData();
    formData.set("mode", "link_existing");
    formData.set("post_id", "SANITIZED_POST");
    formData.set("clip_group", "Existing Group");

    await expect(
      saveContentLabel(initialLabelingActionState, formData),
    ).resolves.toEqual({
      status: "error",
      message: "Complete the required fields and check any entered values.",
    });
    expect(mocks.requireAuthorizedUser).not.toHaveBeenCalled();
    expect(mocks.unsafe).not.toHaveBeenCalled();
  });

  it("links an existing group only through the confirmed wrapper mode", async () => {
    const formData = new FormData();
    formData.set("mode", "link_existing");
    formData.set("post_id", "SANITIZED_POST");
    formData.set("clip_group", "Existing Group");
    formData.set("confirm_shared_effect", "on");
    mocks.unsafe.mockResolvedValueOnce([
      {
        result_content_item_id: "00000000-0000-0000-0000-000000000001",
        result_clip_group: "Existing Group",
        affected_post_count: 4,
      },
    ]);

    await expect(
      saveContentLabel(initialLabelingActionState, formData),
    ).resolves.toEqual({
      status: "success",
      message: "Label saved. 4 posts now share this Clip Group.",
    });
    expect(mocks.unsafe).toHaveBeenCalledWith(
      expect.stringContaining("process_content_label_payload_for_web"),
      [
        {
          post_id: "SANITIZED_POST",
          clip_group: "Existing Group",
        },
        "operator@example.invalid",
        "link_existing",
        true,
      ],
      { prepare: false },
    );
  });

  it("fails closed when controlled labeling is disabled", async () => {
    mocks.getServerEnvironment.mockReturnValue({
      CREATOR_ANALYTICS_LABELING_ENABLED: false,
    });

    await expect(
      saveContentLabel(initialLabelingActionState, createLabelForm()),
    ).resolves.toEqual({
      status: "error",
      message: "Controlled labeling is disabled for this deployment.",
    });
    expect(mocks.getServerLabelingClient).not.toHaveBeenCalled();
  });

  it("does not open the database for a non-allowlisted session", async () => {
    mocks.requireAuthorizedUser.mockRejectedValue(new ForbiddenError());

    await expect(
      saveContentLabel(initialLabelingActionState, createLabelForm()),
    ).resolves.toEqual({
      status: "error",
      message: "Your approved session is no longer available. Sign in again.",
    });
    expect(mocks.getServerLabelingClient).not.toHaveBeenCalled();
  });

  it("maps a Sheet ownership race without exposing database details", async () => {
    mocks.unsafe.mockRejectedValue(
      Object.assign(new Error("sensitive database detail"), { code: "P3002" }),
    );

    const result = await saveContentLabel(
      initialLabelingActionState,
      createLabelForm(),
    );

    expect(result).toEqual({
      status: "error",
      message:
        "This post has already moved to Google Sheets. Finish it in the Label Queue sheet.",
    });
    expect(result.message).not.toContain("sensitive database detail");
  });
});
