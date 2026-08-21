# Creator Analytics Database Reference

## Scope and evidence model

This is a migration-derived reference for the effective schema after migration 028. It does not claim that the live Supabase database exactly matches the repository.

- **[Repository-verified]** Derived directly from migrations 001–028.
- **[Handoff-only]** Stated only in the handoff document.
- **[Inference]** Interpretation of SQL behavior.
- **[Live verification required]** Needs a sanitized live catalog or operator confirmation.

Historical and superseded behavior is documented in [Migration Catalog 001-028](<Migration Catalog 001-028.md>). Guardrail interpretation is in [Guardrails and Migration 028](<Guardrails and Migration 028.md>).

## Effective table catalog after migration 028

### `public.organizations`

**[Repository-verified]** Stores Buffer organizations.

Important columns: `buffer_organization_id` primary key, `name`, `created_at`, and `updated_at`. Channels cascade-delete with their organization. An update trigger maintains `updated_at`.

### `public.channels`

**[Repository-verified]** Stores Buffer-connected channels.

Important columns include:

- `buffer_channel_id` primary key;
- `buffer_organization_id` foreign key;
- `service`, `name`, `display_name`, `descriptor`, and `channel_type`;
- `timezone`;
- connection/queue flags;
- `raw_data`;
- first-seen, last-sync, creation, and update timestamps.

The seed migration defines one YouTube and one TikTok channel with `America/Denver`. **[Live verification required]** Current live channels and settings may differ.

### `public.content_items`

**[Repository-verified]** Represents shared labeled content, allowing multiple platform posts to refer to the same clip.

Important columns: UUID `id`, `internal_title`, `game`, `content_type`, `vibe`, `hook_type`, duration, editing intensity, source recording, notes, and timestamps. Migration 008 adds a partial unique index on non-null `internal_title` and uses normalized Clip Group as that field.

**[Repository-verified]** Processing another row with the same Clip Group updates shared label fields on this record; all posts linked through `content_item_id` observe the update.

### `public.posts`

**[Repository-verified]** Stores the synchronized representation of a Buffer post.

Important columns include:

- `buffer_post_id` primary key;
- organization and channel foreign keys;
- nullable `content_item_id` with `ON DELETE SET NULL`;
- `channel_service`, `post_text`, and `status`;
- Buffer creation, due, and sent timestamps;
- external link/post identifiers and `raw_data`;
- sync/audit timestamps;
- `label_queue_exported_at` from migration 007;
- `schedule_evaluated_at` from migration 021.

**[Repository-verified]** Post synchronization updates Buffer-derived fields but does not clear label linkage, export tracking, or evaluation state.

### `public.post_metric_snapshots`

**[Repository-verified]** Stores cumulative metric snapshots, unique per `(buffer_post_id, captured_on)`.

Important columns include capture dates/times, Buffer metric update time, views, reactions, comments, shares, saves, reach, impressions, clicks, engagement rate, watch-time fields, follower gain, and raw metrics JSON. The default capture day is derived in `America/Denver`.

### `public.schedule_recommendations`

**[Repository-verified]** Initial generic recommendation table from migration 001. It stores channel, optional content labels, recommended day/time, confidence, sample size, expected lift, rationale, status, validity dates, and application timestamps.

**[Inference]** Later scheduling logic is primarily view- and proposal-driven; migrations 013–028 do not populate this table. Its live use is unknown.

### `public.automation_runs`

**[Repository-verified]** General automation audit table with automation name, run status, timing, count, error, and JSON details.

**[Live verification required]** No repository function writes to it, so current operational use is unknown.

### `public.scheduling_cadence_settings`

**[Repository-verified]** Composite primary key `(platform, content_format)` with cadence and safety settings:

- posts per week;
- maximum posts per day;
- minimum same-platform gap;
- protected hours;
- recommendation sample and metric-freshness thresholds;
- timezone and active flag.

Seeded effective values:

| Platform/format | Posts/week | Max/day | Min gap | Protected | Active |
| --- | ---: | ---: | ---: | ---: | --- |
| TikTok short form | 14 | 3 | 6 hours | 24 hours | Yes |
| YouTube short form | 14 | 3 | **4 hours** | 24 hours | Yes |
| YouTube long form | 0 | 1 | 24 hours | 48 hours | No |

**[Repository-verified]** Migration 015’s header describes a general six-hour minimum, but the actual YouTube short-form seed is four hours. This discrepancy must remain visible until an operator confirms intent.

### `public.schedule_change_proposals`

**[Repository-verified]** Stores schedule recommendation, approval, application, and audit history.

Important columns include:

- UUID primary key `id`;
- Buffer post, platform, and content format;
- post display fields;
- current and proposed UTC/local timestamps;
- slot/model score, confidence, sample, metrics status, and timezone;
- `approval_status` constrained to `Pending`, `Approved`, `Rejected`, `Applied`, or `Error`;
- decision/application timestamps and result/error messages;
- generation/update timestamps;
- `sheet_exported_at` from migration 017.

**[Repository-verified]** Migration 019 removed the original unique constraint on `buffer_post_id` to preserve multiple historical rows, then added a partial unique index allowing at most one `Pending` or `Approved` proposal per post.

## Effective indexes after migration 028

**[Repository-verified]** Key indexes include:

- organization lookup for channels;
- channel/status, sent time, due time, and content-item lookup for posts;
- partial Label Queue export lookup for unlabeled posts;
- metric post/date lookup plus the unique post/day constraint;
- recommendation channel/status lookup;
- automation name/start lookup;
- unique non-null content-item `internal_title` for Clip Group;
- proposal status, proposed time, and platform lookup;
- partial unique active-proposal index on `buffer_post_id` for `Pending`/`Approved`.

**[Repository-verified]** There is no universal unique constraint preventing a post from having proposal history plus another non-active proposal. Migration 028 prevents new proposal history through the two repository-defined creation functions, not through a table-wide constraint.

## Effective triggers after migration 028

**[Repository-verified]** `set_updated_at()` is attached before update to organizations, channels, content items, posts, and the original generic schedule recommendations table.

**[Repository-verified]** `reset_schedule_proposal_sheet_export()` runs before updates to schedule proposals. It clears `sheet_exported_at` when schedule/display/recommendation fields change, allowing an updated pending proposal to be re-exported.

**[Inference]** The trigger does not clear export state merely because approval status changes, which is consistent with the export view containing only pending proposals.

## Effective functions and RPCs after migration 028

### Ingestion and labeling

| Function | Effective behavior | Granted repository role |
| --- | --- | --- |
| `sync_buffer_posts(jsonb, text)` | Upserts valid Buffer GraphQL post nodes | `service_role` |
| `sync_buffer_post_metrics(jsonb)` | Upserts one metric snapshot per post per Denver date | `service_role` |
| `create_content_item_and_link_posts(...)` | Creates one content item and links multiple existing, currently unlinked posts | `service_role` |
| `mark_label_queue_exported(text)` | Sets export timestamp once | `service_role` |
| `process_content_label_row(...)` | Validates and upserts shared Clip Group labels, then links one post | `service_role` |
| `process_content_label_payload(jsonb)` | JSON wrapper for row processing | `service_role` |

### Scheduling and proposals

| Function | Effective behavior | Granted repository role |
| --- | --- | --- |
| `generate_weekly_slot_plan(text, text)` | Selects ranked weekly platform slots subject to configured sample freshness, per-day limit, and circular weekly gap | `creator_dashboard_reader`, `service_role` |
| `refresh_schedule_proposals(date, integer)` | **Effective migration 028 definition:** creates one-time content-aware pending proposals only when no evaluation lock or proposal history exists; marks successful inserts evaluated | `service_role` |
| `create_content_aware_schedule_proposals(integer)` | **Effective migration 028 definition:** manual limited bridge with the same no-history/evaluation protections; marks successful inserts evaluated | `service_role` |
| `set_schedule_proposal_decision(uuid, text)` | Sets Pending/Approved/Rejected unless already Applied | `service_role` |
| `mark_schedule_proposal_exported(uuid)` | Marks a pending proposal exported once | `service_role` |
| `mark_schedule_proposal_applied(uuid, text)` | Changes Approved to Applied and records result | `service_role` |
| `mark_schedule_proposal_error(uuid, text)` | Changes Approved to Error and records error | `service_role` |

**[Repository-verified]** These database functions do not call Buffer. The external application scenario is responsible for the Buffer mutation.

### Historical/superseded function behavior

- **[Repository-verified]** Migration 016 introduced platform-wide pairing and upsert refresh behavior.
- **[Repository-verified]** Migration 019 allowed repeat historical proposal cycles while limiting active proposals.
- **[Repository-verified]** Migration 020 froze approved proposals and skipped no-ops.
- **[Repository-verified]** Migration 021 introduced the evaluation lock and marked every paired new post evaluated, including no-op matches.
- **[Repository-verified]** Migration 026’s manual content-aware function inserted proposals but did not set `schedule_evaluated_at`.
- **[Repository-verified]** Migration 027 replaced the automated refresh with content-aware generation and marked inserted posts evaluated.
- **[Repository-verified]** Migration 028 replaces both content-aware creation functions with evaluation-lock plus any-history protection.

Earlier definitions are migration history, not the effective post-028 API.

## Effective view catalog after migration 028

### Internal ingestion and operational views

- `latest_post_metrics`: most recently captured metric snapshot per post.
- `dashboard_posts`: enriched post row with channel, local time, labels, latest metrics, and calculated interaction rate.
- `posting_time_summary`: sent-post aggregation by platform/day/hour.
- `content_performance_summary`: sent-post aggregation by content labels.
- `unlabeled_posts_queue`: all posts without a content item.
- `pending_label_queue_exports`: unlabeled posts not yet marked exported.
- `pending_schedule_proposal_exports`: pending schedule proposals not yet exported to Sheets.
- `approved_schedule_changes_ready_to_apply`: approved changes still eligible for external Buffer application.

### Looker/reporting views

- `looker_dashboard_posts`
- `looker_posting_time_summary`
- `looker_content_performance_summary`
- `looker_daily_growth`
- `looker_posting_day_recommendations`
- `looker_time_window_recommendations`
- `looker_posting_recommendation_summary`
- `looker_joint_posting_recommendations`
- `looker_joint_posting_recommendation_summary`
- `looker_scheduling_cadence_settings`
- `looker_weekly_slot_plan`
- `looker_schedule_change_proposals`
- `looker_content_aware_recommendations`
- `looker_content_aware_recommendation_summary`
- `looker_content_aware_fallback_preview`
- `looker_content_aware_shadow_schedule`
- `looker_content_aware_shadow_schedule_summary`
- `looker_content_aware_hybrid_shadow_schedule`
- `looker_content_aware_hybrid_shadow_schedule_summary`
- `looker_content_aware_proposal_preview`
- `looker_content_aware_proposal_preview_summary`

**[Handoff-only]** The live Looker report uses surfaces for totals, averages, platform comparison, recent performance, content performance, and posting-time performance. **[Live verification required]** Which SQL views are actively connected is unknown.

## Reporting-role permissions

**[Repository-verified]** Migration 010 creates login role `creator_dashboard_reader`, makes its transactions read-only by default, and grants curated `looker_*` view access without setting a password.

**[Repository-verified]** Migration 011 makes internal reporting views owner-permission views and revokes the reader’s access to them, intending the reader to use only curated Looker views.

**[Repository-verified]** Migration 012 then grants the reader `SELECT` on `latest_post_metrics`, `dashboard_posts`, `posting_time_summary`, and `content_performance_summary` in addition to the curated views. The effective migration-derived permission set is therefore broader than migration 011’s stated intent.

**[Repository-verified]** Later migrations grant the reader several scheduling/recommendation preview views and execution of `generate_weekly_slot_plan`.

**[Live verification required]** A live grant/ownership export is necessary to determine actual privileges and whether out-of-repository changes exist.

## RLS behavior and application access

**[Repository-verified]** RLS is enabled on:

- all seven tables created in migration 001;
- `scheduling_cadence_settings`;
- `schedule_change_proposals`.

**[Repository-verified]** Migrations 001–028 create no RLS policies.

**[Inference]** With RLS enabled and no applicable policies, ordinary table access is denied even if a role receives a table grant; owners and bypass-RLS roles have different behavior. Security-definer functions and owner-permission views can expose controlled behavior independently of direct table policies.

**[Repository-verified]** The repository does not define an authenticated end-user role model or web-app authorization policy.

**[Live verification required]** Policies, grants, ownership, role membership, and manually created auth objects in the live project.

## Timezone behavior

**[Repository-verified]** Channel and cadence seeds use `America/Denver`. Dashboard publication local time is computed using the channel timezone with a Denver fallback. Proposals convert local timestamps with `AT TIME ZONE`, yielding UTC-aware timestamps and allowing PostgreSQL timezone rules to handle daylight-saving offsets.

**[Repository-verified]** Metric capture day is explicitly Denver-local.

**[Repository-verified]** Several defaults and filters use `current_date`, while content-aware preview calendar generation uses `(now() at time zone timezone_name)::date`.

**[Live verification required]** Database/session timezone and boundary behavior when Make supplies dates near local midnight.

## Application-ready view limitations

`approved_schedule_changes_ready_to_apply` verifies, at query time:

- **[Repository-verified]** Approved status;
- no application timestamp or error;
- synchronized post status remains `scheduled`;
- proposed UTC time remains outside configured protected hours.

It does not independently verify:

- **[Repository-verified]** that Buffer’s current live due time still equals the captured proposal current time;
- **[Repository-verified]** that no same-platform collision has appeared since generation;
- **[Repository-verified]** that proposal timezone equals current channel timezone;
- **[Repository-verified]** that the external Buffer mutation has not already occurred without a successful callback.

Those behaviors require external orchestration or future safeguards and are **[Live verification required]**.
