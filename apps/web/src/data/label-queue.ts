import { z } from "zod";

import type { LabelQueueData, PartialDataError } from "@/data/models";
import { sanitizeExternalUrl } from "@/lib/format";

const numericValue = z
  .union([z.number(), z.string()])
  .transform((value) => Number(value))
  .refine(Number.isFinite);

export const unlabeledQueueRowSchema = z.object({
  buffer_post_id: z.string(),
  platform: z.string(),
  channel_name: z.string().nullable(),
  status: z.string(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
  published_at_local: z.string().nullable(),
  views: numericValue.nullable(),
  latest_metric_date: z.string().nullable(),
});

export const pendingLabelExportRowSchema = z.object({
  buffer_post_id: z.string(),
});

export const clipGroupRelationshipRowSchema = z.object({
  platform: z.string(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
  published_at_utc: z.string().nullable(),
  clip_group: z.string().nullable(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
});

type UnlabeledQueueRow = z.infer<typeof unlabeledQueueRowSchema>;
type PendingLabelExportRow = z.infer<typeof pendingLabelExportRowSchema>;
type ClipGroupRelationshipRow = z.infer<typeof clipGroupRelationshipRowSchema>;

export function buildLabelQueueData(options: {
  unlabeledRows: UnlabeledQueueRow[];
  pendingRows: PendingLabelExportRow[];
  pendingStateAvailable: boolean;
  clipRows: ClipGroupRelationshipRow[];
  partialErrors: PartialDataError[];
}): LabelQueueData {
  const pendingIds = new Set(
    options.pendingRows.map((row) => row.buffer_post_id),
  );
  const pendingCount = options.pendingStateAvailable
    ? options.unlabeledRows.filter((row) => pendingIds.has(row.buffer_post_id))
        .length
    : null;

  const clipGroups = new Map<string, LabelQueueData["clipGroups"][number]>();

  for (const row of options.clipRows) {
    const name = row.clip_group?.trim();
    if (!name) continue;

    const existing = clipGroups.get(name) ?? {
      name,
      game: row.game,
      contentType: row.content_type,
      platforms: [],
      postCount: 0,
      recentPosts: [],
    };

    existing.postCount += 1;
    if (!existing.platforms.includes(row.platform)) {
      existing.platforms.push(row.platform);
      existing.platforms.sort();
    }
    if (existing.recentPosts.length < 3) {
      existing.recentPosts.push({
        platform: row.platform,
        caption: row.post_text?.trim() || "Untitled linked post",
        externalLink: sanitizeExternalUrl(row.external_link),
        publishedAt: row.published_at_utc,
      });
    }
    clipGroups.set(name, existing);
  }

  return {
    summary: {
      unlinked: options.unlabeledRows.length,
      pendingExport: pendingCount,
      exportedStillUnlinked:
        pendingCount === null
          ? null
          : options.unlabeledRows.length - pendingCount,
    },
    items: options.unlabeledRows.map((row) => ({
      platform: row.platform,
      channelName: row.channel_name ?? row.platform,
      sourceStatus: row.status,
      caption: row.post_text?.trim() || "Untitled unlinked post",
      externalLink: sanitizeExternalUrl(row.external_link),
      publishedAtLocal: row.published_at_local,
      views: row.views,
      latestMetricDate: row.latest_metric_date,
      queueState: !options.pendingStateAvailable
        ? "export_state_unavailable"
        : pendingIds.has(row.buffer_post_id)
          ? "pending_export"
          : "exported_unlinked",
    })),
    clipGroups: Array.from(clipGroups.values()).sort(
      (left, right) =>
        right.postCount - left.postCount || left.name.localeCompare(right.name),
    ),
    partialErrors: options.partialErrors,
  };
}
