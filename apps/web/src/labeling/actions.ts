"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

import { requireAuthorizedUser } from "@/auth/authorization.server";
import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import { getServerEnvironment } from "@/config/env-server";
import { getServerLabelingClient } from "@/lib/database/server-data";
import {
  labelContentTypes,
  labelEditingIntensities,
  labelGames,
  labelHookTypes,
  labelVibes,
} from "@/labeling/options";
import type { LabelingActionState } from "@/labeling/state";

const optionalText = (maximumLength: number) =>
  z.preprocess(
    (value) =>
      value === null || (typeof value === "string" && value.trim() === "")
        ? undefined
        : value,
    z.string().trim().max(maximumLength).optional(),
  );

const sharedFields = {
  post_id: z.string().trim().min(1).max(255),
  clip_group: z.string().trim().min(1).max(160),
};

const createLabelSchema = z.object({
  ...sharedFields,
  mode: z.literal("create"),
  game: z.enum(labelGames),
  content_type: z.enum(labelContentTypes),
  vibe: z.enum(labelVibes),
  hook_type: z.preprocess(
    (value) => (value === "" || value === null ? undefined : value),
    z.enum(labelHookTypes).optional(),
  ),
  duration_seconds: z.preprocess(
    (value) => (value === "" || value === null ? undefined : value),
    z.coerce.number().int().min(0).max(86_400).optional(),
  ),
  editing_intensity: z.preprocess(
    (value) => (value === "" || value === null ? undefined : value),
    z.enum(labelEditingIntensities).optional(),
  ),
  source_recording: optionalText(255),
  notes: optionalText(2_000),
});

const linkExistingLabelSchema = z.object({
  ...sharedFields,
  mode: z.literal("link_existing"),
  confirm_shared_effect: z.literal("on"),
});

const labelSubmissionSchema = z.discriminatedUnion("mode", [
  createLabelSchema,
  linkExistingLabelSchema,
]);

type LabelingDatabaseResult = {
  result_content_item_id: string;
  result_clip_group: string;
  affected_post_count: number;
};

function databaseErrorCode(error: unknown): string | null {
  if (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof error.code === "string"
  ) {
    return error.code;
  }
  return null;
}

function databaseFailureMessage(error: unknown): string {
  switch (databaseErrorCode(error)) {
    case "P3001":
      return "This post was labeled by another workflow. Refresh to see its current state.";
    case "P3002":
      return "This post has already moved to Google Sheets. Finish it in the Label Queue sheet.";
    case "P3003":
      return "Confirm the shared Clip Group effect before saving.";
    case "P3004":
      return "This post is no longer available. Refresh the page.";
    case "P3005":
      return "That Clip Group already exists. Choose it from the existing-group list instead.";
    case "P3006":
      return "That Clip Group changed or was removed. Refresh the page and choose again.";
    case "22023":
      return "One or more label values are no longer accepted. Refresh and check the form.";
    default:
      return "The label could not be saved. Nothing was partially applied; refresh and try again.";
  }
}

export async function saveContentLabel(
  _previousState: LabelingActionState,
  formData: FormData,
): Promise<LabelingActionState> {
  const parsed = labelSubmissionSchema.safeParse({
    mode: formData.get("mode"),
    post_id: formData.get("post_id"),
    clip_group: formData.get("clip_group"),
    game: formData.get("game"),
    content_type: formData.get("content_type"),
    vibe: formData.get("vibe"),
    hook_type: formData.get("hook_type"),
    duration_seconds: formData.get("duration_seconds"),
    editing_intensity: formData.get("editing_intensity"),
    source_recording: formData.get("source_recording"),
    notes: formData.get("notes"),
    confirm_shared_effect: formData.get("confirm_shared_effect"),
  });

  if (!parsed.success) {
    return {
      status: "error",
      message: "Complete the required fields and check any entered values.",
    };
  }

  try {
    const authorizedUser = await requireAuthorizedUser();
    const environment = getServerEnvironment();

    if (!environment.CREATOR_ANALYTICS_LABELING_ENABLED) {
      return {
        status: "error",
        message: "Controlled labeling is disabled for this deployment.",
      };
    }

    const { mode, post_id, clip_group } = parsed.data;
    const payload =
      mode === "create"
        ? {
            post_id,
            clip_group,
            game: parsed.data.game,
            content_type: parsed.data.content_type,
            vibe: parsed.data.vibe,
            hook_type: parsed.data.hook_type,
            duration_seconds: parsed.data.duration_seconds,
            editing_intensity: parsed.data.editing_intensity,
            source_recording: parsed.data.source_recording,
            notes: parsed.data.notes,
          }
        : { post_id, clip_group };

    const database = getServerLabelingClient();
    const result = await database.begin(async (transaction) => {
      const rows = await transaction.unsafe(
        [
          "select result_content_item_id, result_clip_group, affected_post_count",
          "from public.process_content_label_payload_for_web(",
          "$1::jsonb, $2::text, $3::text, $4::boolean",
          ")",
        ].join(" "),
        [payload, authorizedUser.email, mode, mode === "link_existing"],
        { prepare: false },
      );

      return rows[0] as unknown as LabelingDatabaseResult | undefined;
    });

    if (!result) {
      throw new Error("The labeling function returned no result.");
    }

    revalidatePath("/label-queue");
    revalidatePath("/dashboard");
    revalidatePath("/top-posts");
    revalidatePath("/analytics");

    return {
      status: "success",
      message:
        result.affected_post_count === 1
          ? "Label saved. The post is now linked to its new Clip Group."
          : `Label saved. ${result.affected_post_count} posts now share this Clip Group.`,
    };
  } catch (error) {
    if (isAuthorizationError(error)) {
      return {
        status: "error",
        message: "Your approved session is no longer available. Sign in again.",
      };
    }

    if (error instanceof ConfigurationError) {
      return {
        status: "error",
        message: "Controlled labeling is not configured for this deployment.",
      };
    }

    return { status: "error", message: databaseFailureMessage(error) };
  }
}
