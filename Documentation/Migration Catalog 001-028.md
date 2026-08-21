# Migration Catalog 001–028

## Reading this catalog

This catalog records migration history in numerical order and distinguishes historical definitions from effective post-028 behavior.

- **[Repository-verified]** All catalog entries summarize the SQL files themselves.
- **[Handoff-only]** Operational outcomes reported only by the handoff are explicitly marked.
- **[Inference]** Interpretations are labeled.
- **[Live verification required]** The repository does not prove which migrations are applied in Supabase.

## Catalog

| Migration | Purpose and principal objects | Effective status after 028 |
| --- | --- | --- |
| 001 `initial_schema` | Enables `pgcrypto`; creates `set_updated_at`, seven core tables, base indexes/triggers, and enables RLS. | Core schema remains. No repository-defined RLS policies were added later. |
| 002 `seed_buffer_accounts` | Upserts one organization plus YouTube and TikTok channels using Denver time. | Seed history remains; live account state requires verification. |
| 003 `sync_buffer_posts_function` | Adds service-role `sync_buffer_posts(jsonb, text)` for GraphQL edge/node upserts. | Effective ingestion RPC. |
| 004 `sync_buffer_metrics_function` | Adds service-role daily metric snapshot upsert using Denver capture date. | Effective metric RPC. |
| 005 `dashboard_views` | Adds latest metrics, enriched posts, posting-time summary, and content-performance summary views. | Views remain foundational; security behavior was amended by 011–012. |
| 006 `content_labeling_tools` | Adds unlabeled queue and multi-post content-item creation/linking RPC. | Remains available; later row/payload workflow adds shared Clip Group behavior. |
| 007 `label_queue_export_tracking` | Adds post export timestamp, pending export view, and mark-exported RPC. | Effective Label Queue export tracking. |
| 008 `process_content_label_row` | Makes non-null content item title unique; normalizes Clip Group; upserts shared labels and links one post. | Effective row-level label processor. Shared updates affect all linked posts. |
| 009 `process_content_label_payload` | Adds JSON wrapper around migration 008 processor and requests PostgREST schema reload. | Effective payload processor. |
| 010 `looker_reporting_access` | Creates read-only login role and curated Looker views, including daily growth; intentionally does not set a password. | Base reporting role/views remain. Grants were changed later. |
| 011 `fix_reporting_view_permissions` | Makes nested reporting views owner-permission views, revokes reader access to internals, and grants curated views only. | Its narrow-access intent is superseded by migration 012’s broader grant. |
| 012 `grant_reader_nested_view_access` | Grants the reporting role both internal nested views and curated Looker views. | Effective repository-derived access is broader than 011 intended. |
| 013 `posting_time_recommendations` | Adds separate platform day and four-hour-window recommendations, shrinkage, scoring, confidence, freshness, and combined summary. | Remains reporting/analysis surface; content-aware model later builds on joint model. |
| 014 `joint_posting_recommendations` | Scores day and time window jointly with stronger platform shrinkage. | Remains the platform-overall recommendation and fallback source. |
| 015 `scheduling_cadence_and_weekly_slots` | Adds cadence table, seeds 14+14 short-form targets, weekly slot generator, and reporting views. | Effective cadence source. Actual YouTube short-form gap seed is four hours despite six-hour header language. |
| 016 `schedule_proposal_approval_queue` | Creates proposal table, initial platform-wide refresh, decision RPC, and proposal reporting view. | Table/decision/view remain; refresh definition is superseded. Original one-row-per-post uniqueness was removed by 019. |
| 017 `schedule_proposal_sheet_export` | Adds sheet export timestamp, reset trigger, pending export view, and mark-exported RPC. | Effective Schedule Approvals export tracking. |
| 018 `approved_schedule_changes_for_buffer` | Adds application-ready view plus applied/error result RPCs. Does not call Buffer. | Effective external application handoff. Limitations remain around stale schedule and collision revalidation. |
| 019 `allow_repeat_schedule_cycles` | Removes universal post uniqueness, adds one-active-proposal partial unique index, and patches refresh conflict target. | Historical proposals are allowed; at most one Pending/Approved row is enforced. Migration 028 procedurally prevents new history via named creation paths. |
| 020 `harden_schedule_proposal_refresh` | Dynamically patches refresh to skip no-op changes and update only Pending proposals. | Behavior was carried forward conceptually; function itself was later replaced. |
| 021 `lock_evaluated_schedule_posts` | Adds and backfills `schedule_evaluated_at`; replaces refresh to evaluate posts once, including marking paired no-op posts. | Column/backfill remain. Refresh definition was replaced by 027 and 028, whose marking semantics are narrower. |
| 022 `content_aware_recommendation_preview_fixed` | Adds hierarchical content models, top-slot summaries, thresholds, confidence/freshness, and fallback preview. | Effective content-aware recommendation foundation. Filename header omits `_fixed`, but SQL objects are clear. |
| 023 `content_aware_shadow_schedule_preview` | Adds read-only direct content-aware shadow assignment with fixed local day +2 through +23 calendar and guardrail flags. | Remains an upstream preview dependency. Does not mutate proposals. |
| 024 `content_aware_hybrid_shadow_scheduler` | Adds greedy content-aware assignment to unique platform weekly-template slots within each cadence cycle. | Effective hybrid scheduling preview used downstream. Not a global optimizer. |
| 025 `content_aware_proposal_preview` | Maps hybrid rows into proposal shape; filters no-ops; blocks active proposals and failed guardrails; adds summary. | Effective proposal eligibility preview. |
| 026 `create_content_aware_schedule_proposals` | Adds manual bridge from preview to pending proposal rows. | **Superseded by 028.** Original defect: successful inserts did not set `posts.schedule_evaluated_at`. |
| 027 `content_aware_schedule_automation` | Replaces automated refresh with content-aware preview while retaining RPC signature; marks inserted rows evaluated. | **Superseded by 028.** It relied on evaluation state but had no any-history exclusion. |
| 028 `prevent_duplicate_content_aware_proposals_v2` | Backfills evaluation locks from all proposal history, rejects certain accidental pending duplicates without deleting them, and hardens manual/automatic creation with evaluation and history checks. | Effective proposal-creation behavior. Does not call or edit Buffer. |

## Historical evolution of proposal uniqueness

1. **[Repository-verified]** Migration 016 defines `buffer_post_id text not null unique`, permitting only one proposal row per post.
2. **[Repository-verified]** Migration 019 removes that constraint to allow historical cycles, then enforces one active `Pending`/`Approved` proposal with a partial unique index.
3. **[Repository-verified]** Migration 021 introduces a post-level evaluation timestamp and backfills proposal history.
4. **[Repository-verified]** Migration 026 opens the content-aware manual path but fails to mark inserted posts evaluated.
5. **[Repository-verified]** Migration 027 relies on null evaluation state for automatic eligibility, so a post created through 026 can become eligible again after its proposal leaves active status.
6. **[Repository-verified]** Migration 028 backfills the missing locks and requires both a null evaluation timestamp and absence of any proposal history in the manual and automatic content-aware functions.

## Effective post-migration-028 proposal behavior

**[Repository-verified]** The effective `create_content_aware_schedule_proposals(integer)` and `refresh_schedule_proposals(date, integer)` definitions both require:

- a matching post with `schedule_evaluated_at IS NULL`;
- no existing proposal row of any status for that Buffer post;
- a ready proposal-preview row;
- no active proposal;
- recommendation and hybrid readiness;
- passing hybrid guardrails;
- a real schedule change;
- a proposed time beyond protected hours.

The automated refresh additionally filters proposed local date using its start date and horizon. A successful insert marks the post evaluated. The partial active-proposal index remains a concurrency/backstop control.

**[Repository-verified]** This is procedural one-proposal-history protection for the two defined functions, not a universal database constraint against other insert paths.

## Migration 028 data remediation

**[Repository-verified]** Migration 028:

- fills null `posts.schedule_evaluated_at` from the earliest proposal `generated_at` for every post with history;
- converts a `Pending` proposal to `Rejected` if an earlier proposal for that post has terminal status `Applied`, `Rejected`, or `Error`;
- preserves the duplicate row and adds an explanatory result message rather than deleting it.

**[Inference]** Equal `generated_at` timestamps do not satisfy the strict “earlier than” comparison. A live validation query should test for any residual duplicates regardless of timestamp equality.

## Handoff-reported results, not repository proof

- **[Handoff-only]** After migration 028, posts with history but no evaluation lock were reported as zero.
- **[Handoff-only]** Accidental pending duplicates remaining were reported as zero.
- **[Handoff-only]** Eighteen duplicate pending proposals were reportedly rejected.
- **[Handoff-only]** A controlled refresh reportedly returned zero old proposals.
- **[Handoff-only]** Twelve new cross-platform posts reportedly produced exactly twelve fresh proposals and no resurfaced applied posts.
- **[Live verification required]** The handoff says those twelve were approved but still awaiting the normal application cycle. Final Buffer/application results remain unverified.

## Live migration verification required

A sanitized schema/catalog export should confirm:

- which migrations were applied and in what order;
- effective function definitions and owners;
- current indexes and constraints;
- current RLS policies and grants;
- the migration 028 data-state assertions;
- absence of out-of-repository replacements or manual patches.
