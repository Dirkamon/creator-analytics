"use server";

import { revalidatePath } from "next/cache";
import { requireAuthorizedUser } from "@/auth/authorization.server";
import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import { getPreferencesConfiguration } from "@/config/preferences-server";
import { getServerPreferencesClient } from "@/lib/database/server-data";
import {
  preferencesFormSchema,
  type PreferencesActionState,
} from "@/scheduling/preferences";

export async function savePostingPreferences(
  revision: number,
  _state: PreferencesActionState,
  form: FormData,
): Promise<PreferencesActionState> {
  const input = preferencesFormSchema.safeParse({
    revision,
    tiktok_weekly: form.get("tiktok_weekly"),
    tiktok_ceiling: form.get("tiktok_ceiling"),
    youtube_weekly: form.get("youtube_weekly"),
    youtube_ceiling: form.get("youtube_ceiling"),
    enabled: form.get("enabled"),
    confirm: form.get("confirm"),
  });
  if (!input.success)
    return {
      status: "error",
      message:
        "Use whole-number targets within the daily limits, then confirm your changes.",
    };
  try {
    const user = await requireAuthorizedUser();
    const configuration = getPreferencesConfiguration();
    const value = input.data;
    if (value.enabled && !configuration.activationAllowed) {
      return {
        status: "error",
        message:
          "Production activation is locked for this rollout. Keep the new rules off; no changes were submitted.",
      };
    }
    const rows = await getServerPreferencesClient().unsafe(
      "select public.save_scheduling_preferences($1::integer,$2::integer,$3::integer,$4::integer,$5::integer,$6::boolean,$7::text) as revision",
      [
        value.revision,
        value.tiktok_weekly,
        value.tiktok_ceiling,
        value.youtube_weekly,
        value.youtube_ceiling,
        value.enabled,
        user.email,
      ],
      { prepare: false },
    );
    if (rows[0]?.revision !== revision + 1)
      throw new Error("Unexpected save result");
    revalidatePath("/scheduling-preferences");
    return {
      status: "success",
      revision: rows[0].revision,
      saved: {
        enabled: value.enabled,
        tiktok_weekly: value.tiktok_weekly,
        tiktok_ceiling: value.tiktok_ceiling,
        youtube_weekly: value.youtube_weekly,
        youtube_ceiling: value.youtube_ceiling,
      },
      message: `Saved in ${configuration.environment}. ${value.enabled ? "New proposal refreshes will use these rules." : "The new rules remain off."} No posts were moved.`,
    };
  } catch (error) {
    if (isAuthorizationError(error))
      return {
        status: "error",
        message: "Sign in with your approved account before saving.",
      };
    if (error instanceof ConfigurationError)
      return {
        status: "error",
        message:
          "Scheduling preferences are not configured yet. No changes were submitted.",
      };
    const code =
      typeof error === "object" && error !== null && "code" in error
        ? error.code
        : null;
    return {
      status: "error",
      message:
        code === "P4101"
          ? "These settings changed. Reload the page and review them before saving."
          : code === "P4102"
            ? "Resolve pending and approved proposals before changing these settings."
            : "The save could not be confirmed. Reload to check the saved settings before trying again.",
    };
  }
}
