import "server-only";

import { z } from "zod";

import { isAuthorizationError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import type { PartialDataError, UpcomingPostsData } from "@/data/models";
import {
  proposalStatusQuery,
  upcomingPostsQuery,
} from "@/data/query-specifications";
import type { ReadOnlyReader } from "@/data/read-only";
import { serverReadOnlyReader } from "@/data/read-only.server";
import { sanitizeExternalUrl } from "@/lib/format";

const upcomingPostSchema = z.object({
  buffer_post_id: z.string(),
  platform: z.string(),
  channel_name: z.string().nullable(),
  channel_display_name: z.string().nullable(),
  status: z.string(),
  post_text: z.string().nullable(),
  external_link: z.string().nullable(),
  due_at: z.string(),
  label_status: z.string(),
  internal_title: z.string().nullable(),
  game: z.string().nullable(),
  content_type: z.string().nullable(),
  last_synced_at: z.string().nullable(),
});

const proposalSchema = z.object({
  buffer_post_id: z.string(),
  approval_status: z.string(),
  proposed_due_at_utc: z.string(),
  confidence: z.string().nullable(),
  metrics_status: z.string().nullable(),
  updated_at: z.string(),
});

function rethrowAccessErrors(error: unknown): void {
  if (isAuthorizationError(error) || error instanceof ConfigurationError) {
    throw error;
  }
}

export async function getUpcomingPostsData(
  options: {
    reader?: ReadOnlyReader;
    now?: Date;
  } = {},
): Promise<UpcomingPostsData> {
  const reader = options.reader ?? serverReadOnlyReader;
  const now = options.now ?? new Date();
  const partialErrors: PartialDataError[] = [];
  let postRows: z.infer<typeof upcomingPostSchema>[] = [];

  try {
    postRows = z
      .array(upcomingPostSchema)
      .parse(await reader.select(upcomingPostsQuery(now.toISOString())));
  } catch (error) {
    rethrowAccessErrors(error);
    partialErrors.push({
      section: "Upcoming schedule",
      message: "Upcoming schedule data is temporarily unavailable.",
    });
  }

  if (postRows.length === 0) {
    return { posts: [], partialErrors };
  }

  let proposalRows: z.infer<typeof proposalSchema>[] = [];

  try {
    proposalRows = z
      .array(proposalSchema)
      .parse(
        await reader.select(
          proposalStatusQuery(postRows.map((post) => post.buffer_post_id)),
        ),
      );
  } catch (error) {
    rethrowAccessErrors(error);
    partialErrors.push({
      section: "Proposal status",
      message: "Proposal status is temporarily unavailable.",
    });
  }

  const latestProposalByPost = new Map<
    string,
    z.infer<typeof proposalSchema>
  >();
  for (const proposal of proposalRows) {
    if (!latestProposalByPost.has(proposal.buffer_post_id)) {
      latestProposalByPost.set(proposal.buffer_post_id, proposal);
    }
  }

  return {
    posts: postRows.map((post) => {
      const proposal = latestProposalByPost.get(post.buffer_post_id);
      return {
        key: post.buffer_post_id,
        platform: post.platform,
        channelName:
          post.channel_display_name ?? post.channel_name ?? post.platform,
        caption: post.post_text?.trim() || "Untitled scheduled post",
        externalLink: sanitizeExternalUrl(post.external_link),
        dueAt: post.due_at,
        labelStatus: post.label_status,
        clipGroup: post.internal_title,
        game: post.game,
        contentType: post.content_type,
        lastSyncedAt: post.last_synced_at,
        proposal: proposal
          ? {
              status: proposal.approval_status,
              proposedDueAt: proposal.proposed_due_at_utc,
              confidence: proposal.confidence,
              metricsStatus: proposal.metrics_status,
            }
          : null,
      };
    }),
    partialErrors,
  };
}
