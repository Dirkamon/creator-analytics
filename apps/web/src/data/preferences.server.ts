import "server-only";

import { requireAuthorizedUser } from "@/auth/authorization.server";
import { getPreferencesConfiguration } from "@/config/preferences-server";
import {
  readOnlyRelationPolicies,
  type ReadOnlyReader,
} from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";
import {
  savedPreferenceSchema,
  coverageSchema,
} from "@/scheduling/preferences";

export async function loadSchedulingPreferences(
  reader: ReadOnlyReader = serverReadOnlyReader,
) {
  await requireAuthorizedUser();
  const { environment, activationAllowed } = getPreferencesConfiguration();
  const [settingsRows, coverageRows] = await Promise.all([
    reader.select({
      relation: "scheduling_preferences",
      columns:
        readOnlyRelationPolicies.scheduling_preferences.selectableColumns.join(
          ",",
        ),
      order: [{ column: "platform", ascending: true }],
      limit: 3,
    }),
    reader.select({
      relation: "scheduling_coverage",
      columns:
        readOnlyRelationPolicies.scheduling_coverage.selectableColumns.join(
          ",",
        ),
      order: [
        { column: "local_date", ascending: true },
        { column: "platform", ascending: true },
        { column: "buffer_channel_id", ascending: true },
      ],
      limit: 500,
    }),
  ]);
  const settings = savedPreferenceSchema.array().length(2).parse(settingsRows);
  if (
    new Set(settings.map((s) => s.platform)).size !== 2 ||
    settings.some(
      (s) =>
        s.revision !== settings[0].revision ||
        s.enabled !== settings[0].enabled ||
        s.posts_per_week > s.max_posts_per_day * 7,
    )
  ) {
    throw new Error("Inconsistent scheduling preferences");
  }
  if (coverageRows.length === 0 || coverageRows.length >= 500)
    throw new Error("Scheduling coverage is incomplete");
  return {
    settings,
    coverage: coverageSchema.array().parse(coverageRows),
    environment,
    activationAllowed,
  };
}
