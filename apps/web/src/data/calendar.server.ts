import "server-only";

import { z } from "zod";
import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import {
  calendarMonth,
  calendarQueryBounds,
  type CalendarData,
  type CalendarPost,
} from "@/data/calendar";
import { calendarPostsQuery } from "@/data/query-specifications";
import type { ReadOnlyReader } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";
import { localDateKey, sanitizeExternalUrl } from "@/lib/format";

const timestamp = z
  .string()
  .refine((value) => Number.isFinite(Date.parse(value)));
const common = z.object({
  buffer_post_id: z.string(),
  platform: z.string(),
  channel_name: z.string().nullable(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
});
const scheduledSchema = common.extend({
  due_at: timestamp,
  internal_title: z.string().nullable(),
});
const publishedSchema = common.extend({
  published_at_utc: timestamp,
  clip_group: z.string().nullable(),
});

export async function getCalendarData(
  options: {
    month?: unknown;
    now?: Date;
    reader?: ReadOnlyReader;
  } = {},
): Promise<CalendarData> {
  const now = options.now ?? new Date();
  const month = calendarMonth(options.month, now);
  const reader = options.reader ?? serverReadOnlyReader;
  const bounds = calendarQueryBounds(month);

  async function read(status: CalendarPost["status"]) {
    const posts: CalendarPost[] = [];
    try {
      for (let page = 0; page < 20; page += 1) {
        const rows = await reader.select(
          calendarPostsQuery(status, bounds, page),
        );
        for (const raw of rows) {
          const row =
            status === "scheduled"
              ? scheduledSchema.parse(raw)
              : publishedSchema.parse(raw);
          const at = "due_at" in row ? row.due_at : row.published_at_utc;
          if (!localDateKey(at).startsWith(`${month}-`)) continue;
          const caption = row.post_text?.trim() || "Untitled post";
          const title =
            ("internal_title" in row
              ? row.internal_title
              : row.clip_group
            )?.trim() || caption;
          posts.push({
            key: row.buffer_post_id,
            title,
            caption,
            platform: row.platform,
            channel: row.channel_name,
            at,
            status,
            externalLink: sanitizeExternalUrl(row.external_link),
          });
        }
        if (rows.length < 500) return { posts, error: null };
      }
      // Never present a silently truncated month as an exact count.
      throw new Error("Calendar row limit reached");
    } catch (error) {
      if (isAuthorizationError(error) || error instanceof ConfigurationError)
        throw error;
      return {
        posts: [],
        error: {
          section:
            status === "scheduled" ? "Scheduled posts" : "Published posts",
          message:
            "These posts could not be loaded. Counts may be incomplete; try refreshing the page.",
        },
      };
    }
  }

  const [scheduled, published] = await Promise.all([
    read("scheduled"),
    read("published"),
  ]);
  // A post may publish between the two reads; show its published record once.
  const unique = new Map<string, CalendarPost>();
  for (const post of [...scheduled.posts, ...published.posts])
    unique.set(post.key, post);
  return {
    month,
    today: localDateKey(now),
    posts: [...unique.values()],
    partialErrors: [scheduled.error, published.error].filter(
      (error) => error !== null,
    ),
  };
}
