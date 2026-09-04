# Labeling and Scheduling Workflows

## Evidence labels

- **[Repository-verified]** Directly supported by migrations 001–028 or inspected repository documentation.
- **[Handoff-only]** Supplied by the handoff but not demonstrated by repository implementation.
- **[Inference]** Reasoned from repository structures.
- **[Live verification required]** Needs sanitized production artifacts or operator confirmation.

This document describes effective behavior after migration 028. Historical proposal behavior is separated in [Migration Catalog 001-028](<Migration Catalog 001-028.md>).

## End-to-end Buffer post ingestion

### External acquisition

**[Handoff-only]** The active `Buffer to Supabase – Post Sync` Make scenario retrieves scheduled and published Buffer posts.

**[Live verification required]** Exact Buffer query, pagination, date range, status filters, deletion/cancellation behavior, Make schedule, retry policy, and concurrency are outside the repository.

### Database synchronization

**[Repository-verified]** `sync_buffer_posts(p_posts, p_organization_id)` expects a JSON array of Buffer GraphQL-style edges. For each element it:

1. reads `edge.node`;
2. skips a node lacking `id` or `channelId`;
3. parses Buffer timestamps as `timestamptz` when present;
4. inserts or updates the post by `buffer_post_id`;
5. stores the full node as `raw_data` and updates synchronization timestamps.

**[Repository-verified]** An upsert does not overwrite local workflow fields that are absent from the RPC update list: content linkage, Label Queue export timestamp, and schedule evaluation timestamp.

**[Inference]** This separation protects operator labeling and scheduling workflow state during recurring Buffer synchronization.

## End-to-end Buffer metrics ingestion

### External acquisition

**[Handoff-only]** `Buffer to Supabase – Daily Metrics` collects Buffer analytics daily.

**[Live verification required]** The queried post range, platform metric coverage, paging, API latency, Make schedule, and error handling are unknown.

### Database snapshot behavior

**[Repository-verified]** `sync_buffer_post_metrics(p_posts)`:

- requires a JSON array;
- skips posts without an ID or metrics array;
- normalizes metric names by removing punctuation and lowercasing;
- recognizes views, reactions, comments, shares, saves, reach, impressions, clicks/link clicks, engagement rate, and follows/followers gained;
- leaves missing or nonnumeric metrics null;
- stores raw metrics;
- upserts by `(buffer_post_id, captured_on)`.

**[Repository-verified]** `captured_on` is the current calendar date in `America/Denver`. Repeated runs on the same Denver day overwrite that day’s snapshot rather than append another daily point.

**[Repository-verified]** `looker_daily_growth` calculates nonnegative day-over-day gains and excludes the first snapshot for each post to avoid treating the first cumulative total as one day’s growth.

**[Handoff-only]** Buffer reporting delay should be considered when judging recent posts.

## Label Queue lifecycle

### Repository-defined portion

1. **[Repository-verified]** A synchronized post is considered unlabeled when `posts.content_item_id IS NULL`.
2. **[Repository-verified]** `pending_label_queue_exports` requires `label_queue_exported_at IS NULL`, but migration 036 revokes direct service-role access so Make cannot fetch without claiming.
3. **[Repository-verified]** `claim_pending_label_queue_exports(limit)` locks and claims eligible rows with opaque per-row tokens. Concurrent claimers skip locked rows.
4. **[Repository-verified]** `mark_label_queue_exported(post_id, claim_token)` finalizes only the exact unlinked, unexported row/token pair. The legacy one-argument marker is no longer executable by `service_role`.
5. **[Repository-verified]** A database trigger rejects any content link while an unfinalized Make claim owns the row. Conversely, claim selection excludes rows already linked by the app.
6. **[Repository-verified]** `process_content_label_payload(jsonb)` parses a flexible JSON object and delegates to `process_content_label_row`.
7. **[Repository-verified]** Required label-processing inputs are post ID, Clip Group, game, content type, and vibe. Hook, duration, editing intensity, source recording, and notes are optional.
8. **[Repository-verified]** An already-linked post returns its current content item without changing the shared item.

### Sheet/Make portion

**[Handoff-only]** The human-facing lifecycle is:

`Unlabeled → Ready → Processed`

**[Handoff-only]** `Supabase to Google Sheets – Label Queue` creates the sheet row, an operator supplies labels and sets `Ready`, and `Google Sheets to Supabase – Process Labels` processes it and changes the sheet row to `Processed`.

**[Repository-verified]** The database contains no column implementing those three sheet statuses. It only represents unlabeled/labeled through `content_item_id` plus a separate export timestamp.

**[Live verification required]** Exact headers, validations, status spelling/case, formulas, error states, retries, duplicate detection, row keys, and operator correction behavior.

## Shared Clip Group behavior

**[Repository-verified]** Clip Group is normalized with `lower(nullif(btrim(...), ''))` and stored as `content_items.internal_title`. A partial unique index ensures a non-null normalized title identifies at most one content item.

**[Repository-verified]** Posts for TikTok and YouTube can therefore share one `content_items` record through their `content_item_id` foreign keys.

**[Repository-verified]** When a new, unlinked post is processed with an existing Clip Group, the shared record is updated:

- required game, content type, and vibe replace existing values;
- optional fields replace existing values only when the new input is non-null;
- the new post is linked to the shared record.

**[Repository-verified]** Because labels live on the shared content item, updating them through one platform row changes the labels observed by every linked post.

**[Inference]** A future interface should display the affected linked posts before editing a shared Clip Group and should treat shared label updates as a multi-post operation.

**[Live verification required]** Whether Sheets intentionally permits conflicting labels between two rows in the same Clip Group and how operators resolve them.

## Recommendation inputs

**[Repository-verified]** Recommendation views use sent posts with positive views and a local publication day/hour. Content-aware views additionally require non-null game, content type, and vibe. Null hook is normalized to `(no hook)` for matching.

**[Repository-verified]** Posting time is divided into six four-hour windows:

- 12:00–3:59 AM;
- 4:00–7:59 AM;
- 8:00–11:59 AM;
- 12:00–3:59 PM;
- 4:00–7:59 PM;
- 8:00–11:59 PM.

**[Repository-verified]** Exact template times use each window’s midpoint: 2 AM, 6 AM, 10 AM, 2 PM, 6 PM, or 10 PM.

## Recommendation scoring

### Platform day-only and time-only models

**[Repository-verified]** Migration 013 calculates day and time-window scores separately by platform. Group averages are shrunk toward platform averages with a five-post prior. Score weights are:

- 70% adjusted average-view percentile;
- 20% adjusted interaction-rate percentile;
- 10% sample-size percentile.

### Platform joint day/window model

**[Repository-verified]** Migration 014 evaluates day and window together. It uses an eight-post platform prior because joint buckets are more granular. Score weights are:

- 65% adjusted average-view percentile;
- 20% adjusted interaction-rate percentile;
- 15% sample-size percentile.

### Content-aware hierarchy

**[Repository-verified]** The active content-aware hierarchy selects the lowest model priority that meets its group threshold:

| Priority | Model | Minimum group sample |
| ---: | --- | ---: |
| 1 | Game + Content Type + Vibe + Hook | 12 |
| 2 | Game + Content Type + Vibe | 10 |
| 3 | Game + Content Type | 8 |
| 4 | Game | 8 |
| 5 | Platform Overall | Always available when the platform joint model has data |

**[Repository-verified]** Content-aware slots use the joint model’s 65/20/15 weighting and eight-post shrinkage toward platform performance. Eligibility is based on the entire content group sample, while confidence is based on the winning slot’s sample count.

**[Repository-verified]** Fallback reasons are explicit in the views. A platform-level fallback means no more-specific group met its threshold; it does not by itself mean the pipeline failed.

## Confidence, freshness, and readiness

**[Repository-verified]** Joint/content slot confidence is:

- `High` at 12 or more slot posts;
- `Medium` at 7–11;
- `Low` at 4–6;
- `Experimental` below 4.

**[Repository-verified]** Metrics status is `Fresh` at age 0–2 days, `Delayed` at 3–4 days, and `Stale` above 4 days.

**[Repository-verified]** Content recommendation preview readiness requires the content group threshold and metrics no older than two days. Platform fallback readiness is inherited from the platform joint view, which also requires at least four posts in the winning slot and fresh metrics.

**[Handoff-only]** Operators understand `Experimental` as a small-sample/fallback signal, not necessarily an error.

## Cadence and weekly slot generation

**[Repository-verified]** Seeded short-form cadence is 14 TikTok and 14 YouTube posts per week. Long-form YouTube is inactive with zero weekly posts.

**[Repository-verified]** `generate_weekly_slot_plan` selects platform joint-recommendation rows that meet cadence sample and freshness settings, ordered by score and support. It enforces:

- maximum posts per day;
- circular minimum gap across the 168-hour week;
- total selected slots up to `posts_per_week`.

**[Repository-verified]** TikTok’s seeded gap is six hours; YouTube short form’s actual seeded gap is four hours. Migration 015’s introductory comment calls the minimum six hours without noting the YouTube exception.

**[Live verification required]** Operator intent for the YouTube four-versus-six-hour discrepancy and current live cadence values.

## Hybrid content-aware assignment

**[Repository-verified]** The direct shadow scheduler in migration 023 can place repeated preferred content slots on successive weekly occurrences, then flag per-day and same-platform gap conflicts.

**[Repository-verified]** Migration 024 instead retains the existing weekly platform template and divides queued posts into cadence cycles of `posts_per_week` posts. Within each platform/cycle it:

1. orders content-specific posts before platform fallbacks;
2. scores every post against every slot in its cycle;
3. strongly rewards exact content day + window, then same day, same window, nearby day/hour, and platform slot score;
4. greedily assigns the best unused slot to each post;
5. exposes assignment, guardrail, and comparison fields.

**[Repository-verified]** Every selected slot is unique within a platform cadence cycle.

**[Inference]** The recursive greedy algorithm is deterministic given stable inputs, but it is not a global optimization proof. An early post can consume a slot that would have yielded a better overall assignment for later posts.

## Fixed preview calendar and refresh parameters

**[Repository-verified]** Migrations 023–024 generate preview dates from local today +2 through local today +23 for each active platform/timezone.

**[Repository-verified]** Effective `refresh_schedule_proposals(p_start_date, p_horizon_days)` then filters preview rows to local proposed dates between the supplied start date and `start + horizon`.

**[Inference]** The RPC parameters can narrow the fixed preview set but cannot extend it beyond the dates created upstream. This differs from a scheduler whose calendar is generated directly from the parameters.

**[Handoff-only]** Make uses an approximately 48-hour planning runway and 21-day horizon.

**[Live verification required]** Exact arguments Make supplies, especially around local midnight and daylight-saving transitions.

## Effective proposal generation after migration 028

### Preview eligibility

**[Repository-verified]** `looker_content_aware_proposal_preview` includes only actual schedule changes and sets `ready_to_create` when:

- hybrid shadow readiness is true;
- recommendation preview readiness is true;
- hybrid guardrail status is `Pass`;
- the slot stayed inside its cadence cycle;
- there is no active `Pending` or `Approved` proposal.

### Manual creation function

**[Repository-verified]** `create_content_aware_schedule_proposals(p_limit)` additionally requires:

- no post evaluation timestamp;
- no proposal history of any status;
- a proposed time beyond protected hours;
- at most one candidate per Buffer post.

It inserts `Pending` rows, ignores active-proposal conflicts, and marks successful inserts evaluated.

### Automated refresh function

**[Repository-verified]** `refresh_schedule_proposals(p_start_date, p_horizon_days)` applies the same post/history/readiness protections plus the start/horizon local-date filter. Successful inserts are marked evaluated.

**[Repository-verified]** Neither function calls Buffer or makes an approval decision.

## Proposal approval and application lifecycle

### Generation and export

1. **[Repository-verified]** A proposal is inserted as `Pending` with `sheet_exported_at = NULL`.
2. **[Repository-verified]** `pending_schedule_proposal_exports` exposes pending unexported rows.
3. **[Repository-verified]** `mark_schedule_proposal_exported` timestamps a pending row after external export.
4. **[Repository-verified]** A trigger resets export state if important schedule or recommendation fields change.
5. **[Handoff-only]** Make exports rows to the Schedule Approvals sheet.

### Decision

1. **[Handoff-only]** The operator changes the sheet decision to Approved or Rejected.
2. **[Handoff-only]** The Schedule Decisions scenario writes the decision into Supabase before the application scenario runs.
3. **[Repository-verified]** `set_schedule_proposal_decision` normalizes and permits `Pending`, `Approved`, or `Rejected`, updating corresponding timestamps and clearing error state unless the row is already Applied.

### Application handoff

1. **[Repository-verified]** `approved_schedule_changes_ready_to_apply` requires Approved, unapplied, error-free, still-scheduled posts whose proposed time is outside the current protected window.
2. **[Handoff-only]** Make reads this view and updates Buffer.
3. **[Repository-verified]** After an external success, `mark_schedule_proposal_applied` changes the row to Applied and timestamps it. After an external failure, `mark_schedule_proposal_error` changes it to Error.

**[Repository-verified]** The application-ready view does not independently recompute same-platform collisions and does not compare Buffer’s live current schedule to `current_due_at_utc`.

**[Live verification required]** Whether Make performs those checks, how it handles partial failure, and whether Buffer provides conditional/idempotent update semantics.

## Precise meaning of one-time evaluation

**[Repository-verified]** Effective after migration 028, a post is protected from repository-defined content-aware proposal creation when it has either an evaluation timestamp or any proposal history. A newly inserted proposal sets the timestamp.

**[Repository-verified]** Unlike migration 021’s superseded refresh, effective migrations 027–028 do not mark every considered/no-op/blocked post evaluated; they mark only successfully inserted proposals.

**[Inference]** “One-time schedule evaluation” should therefore not be documented as “every eligible post is examined once.” It means “a post that receives proposal history cannot receive another proposal through the two hardened repository functions.” No-op or blocked posts may be reconsidered while they remain otherwise eligible.

## Timezone handling

**[Repository-verified]** Publication and proposal calculations preserve both:

- local timestamp without offset for operator presentation and local calendar logic;
- UTC-aware `timestamptz` for ordering and external application.

**[Repository-verified]** `AT TIME ZONE timezone_name` performs local-to-UTC conversion using PostgreSQL timezone data, including DST rules.

**[Repository-verified]** Channel timezone defaults and cadence seeds use `America/Denver`, but the schema allows different timezone names.

**[Live verification required]** Database/session timezone, current channel/cadence values, Make date construction, Google Sheets timezone, and Buffer display timezone must be compared end to end.

## Unverified 12-post regression

**[Handoff-only]** Six clips, each uploaded to TikTok and YouTube, reportedly produced 12 synchronized, labeled, processed, and newly generated proposals without resurfacing old applied posts. The handoff says all 12 were approved.

**[Live verification required]** The handoff was written before the scheduled decision/application cycle completed. Required final evidence includes 12 applied results, populated timestamps, blank errors, Buffer schedules matching the proposals, and a later refresh producing no duplicate proposals.
