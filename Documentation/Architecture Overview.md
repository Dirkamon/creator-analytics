# Creator Analytics Architecture Overview

## Scope and evidence labels

This document describes the repository as inspected on `dev/web-app` through database migration 028. The existing Buffer, Make, Supabase, Google Sheets, and Looker Studio workflow is the reference implementation. This is documentation only; it does not prescribe a replacement architecture.

Every substantive claim uses one of these evidence labels:

- **[Repository-verified]** Directly supported by `README.md`, a file under `Documentation/`, or migrations 001–028.
- **[Handoff-only]** Stated in `Creator Analytics - Architecture & Project Handoff.txt` but not independently demonstrated by repository code.
- **[Inference]** A reasoned interpretation of repository objects. It is not proof of live behavior.
- **[Live verification required]** Requires a sanitized export or operator confirmation from a production system.

See also:

- [Database Reference](<Database Reference.md>)
- [Migration Catalog 001-028](<Migration Catalog 001-028.md>)
- [Labeling and Scheduling Workflows](<Labeling and Scheduling Workflows.md>)
- [Guardrails and Migration 028](<Guardrails and Migration 028.md>)
- [Web App Interface Boundaries](<Web App Interface Boundaries.md>)
- [Known Unknowns and Safe Next Phase](<Known Unknowns and Safe Next Phase.md>)

## Repository overview

**[Repository-verified]** The repository currently contains a minimal `README.md`, three pre-existing setup/project documents, a handoff text file, and SQL migrations 001–028 under `Database/`. The SQL is the only repository implementation artifact for the backend examined in this pass. There is no web application scaffold in the inspected scope.

**[Repository-verified]** The migration sequence establishes:

- storage for Buffer organizations, channels, posts, daily metric snapshots, content labels, schedule proposals, cadence settings, recommendations, and automation-run records;
- service-role RPCs for post ingestion, metric ingestion, label processing, proposal generation, decision recording, export tracking, and application-result tracking;
- internal and Looker-oriented reporting views;
- a content-aware hybrid scheduling model and proposal preview;
- proposal safety controls culminating in migration 028.

**[Handoff-only]** The project goal is an end-to-end analytics and scheduling system for gaming short-form content, targeting 14 TikTok posts and 14 YouTube Shorts per week while keeping long-form YouTube manual.

## Current production-reference architecture

| Component | Repository-supported responsibility | Operational claims not proven by the repository |
| --- | --- | --- |
| Buffer | Source identifiers, channel metadata, post schedule/status, and metrics are accepted by Supabase RPCs. Approved schedule-change rows are exposed for an external Buffer updater. | **[Handoff-only]** Buffer is the active publisher and scheduling source. **[Live verification required]** Exact API operations, retry behavior, idempotency, and current channel configuration. |
| Make | SQL objects expose service-only queues and RPCs intended for orchestration. Migration comments name Make and preserve the existing `refresh_schedule_proposals(date, integer)` signature. | **[Handoff-only]** Eight named scenarios are active with specific sequencing and approximate run times. **[Live verification required]** Blueprints, schedules, filters, paging, error routes, and concurrency. |
| Supabase/PostgreSQL | **[Repository-verified]** Primary modeled store, reporting layer, recommendation logic, proposal lifecycle, and service-role functions. | **[Live verification required]** Applied migration ledger, exact live object definitions, role ownership, policies, database timezone, extensions, and data state. |
| Google Sheets | SQL provides Label Queue and Schedule Approval export/readback integration points. | **[Handoff-only]** Sheets is the present human-facing interface. **[Live verification required]** Headers, validations, formulas, state transitions, and duplicate/retry handling. |
| Looker Studio | SQL creates a dedicated read-only role and `looker_*` reporting views. | **[Handoff-only]** The live dashboard reports total and average views, platform comparisons, recent performance, posting-time performance, and labeled-content performance. **[Live verification required]** Active data sources, calculated fields, pages, filters, and refresh cadence. |
| Repository | **[Repository-verified]** Holds the migration history and documentation. | **[Handoff-only]** The working Make/Supabase/Sheets system is considered the known-good production baseline, subject to completion of the 12-post regression test. |

## System context and data ownership

**[Repository-verified]** PostgreSQL tables are the modeled source of truth for ingested post, metric, content-label, cadence, and schedule-proposal records. Views derive reporting and scheduling projections without duplicating those records.

**[Inference]** Buffer remains authoritative for whether a post is actually scheduled or published because Supabase only stores synchronized copies and proposal/application audit fields. `mark_schedule_proposal_applied` records an external success but does not itself update Buffer or the `posts.due_at` value.

**[Handoff-only]** Make is the operational coordinator between Buffer, Supabase, and Sheets.

**[Live verification required]** The system of record for operator decisions during partial failures is not established. For example, the repository does not show how a Buffer update that succeeds while the Supabase result callback fails is reconciled.

## Buffer post ingestion

1. **[Handoff-only]** `Buffer to Supabase – Post Sync` queries Buffer posts.
2. **[Repository-verified]** `sync_buffer_posts(p_posts jsonb, p_organization_id text)` requires a JSON array of GraphQL-style `edges`, reads each `edge.node`, skips nodes without an ID or channel ID, and upserts `public.posts` by `buffer_post_id`.
3. **[Repository-verified]** The upsert refreshes organization/channel linkage, platform service, text, status, Buffer timestamps, external link, raw node data, and synchronization timestamps. Existing `content_item_id`, Label Queue export state, and scheduling evaluation state are not overwritten by this RPC.
4. **[Repository-verified]** The RPC is executable only by `service_role` among the standard Supabase client roles revoked in the migration.
5. **[Live verification required]** Query filters, pagination, scheduled-versus-published coverage, deletion handling, polling frequency, and payload mapping in Make.

## Buffer metrics ingestion

1. **[Handoff-only]** `Buffer to Supabase – Daily Metrics` queries Buffer analytics each day.
2. **[Repository-verified]** `sync_buffer_post_metrics(p_posts jsonb)` reads `edge.node.metrics`, normalizes known metric names, and writes one row per post per `America/Denver` calendar date to `post_metric_snapshots`.
3. **[Repository-verified]** The unique key `(buffer_post_id, captured_on)` makes repeated ingestion on the same local day an update rather than an additional snapshot. Missing metrics remain `NULL`; non-numeric values are ignored.
4. **[Repository-verified]** Views select the latest snapshot and calculate a repository-defined interaction rate from reactions, comments, shares, and saves divided by views.
5. **[Handoff-only]** Buffer analytics may be delayed.
6. **[Live verification required]** Actual metric availability by platform, API lag, collection schedule, paging, and error handling.

## Labeling flow

1. **[Repository-verified]** `pending_label_queue_exports` exposes posts whose `content_item_id` and `label_queue_exported_at` are both null.
2. **[Handoff-only]** `Supabase to Google Sheets – Label Queue` adds those rows to a sheet with status `Unlabeled`.
3. **[Handoff-only]** An operator supplies labels and changes the sheet status to `Ready`.
4. **[Repository-verified]** `process_content_label_payload(jsonb)` delegates to `process_content_label_row(...)`, which validates required post ID, Clip Group, game, content type, and vibe.
5. **[Repository-verified]** Clip Group is trimmed, lowercased, stored as `content_items.internal_title`, and protected by a partial unique index. A later row using the same Clip Group upserts the shared `content_items` record and links the post to it.
6. **[Handoff-only]** `Google Sheets to Supabase – Process Labels` changes the sheet row to `Processed` after processing.
7. **[Live verification required]** The exact sheet state machine, error states, operator correction flow, and when export rows are marked exported.

## Scheduling and approval flow

1. **[Repository-verified]** Historical performance is summarized by platform, day, four-hour window, and content-label hierarchy.
2. **[Repository-verified]** The active content-aware model selects the most specific eligible content model, with platform-wide performance as a fallback, then assigns queued posts to unique weekly-template slots inside their cadence cycle.
3. **[Repository-verified]** `looker_content_aware_proposal_preview` excludes no-op schedule changes and identifies rows that pass labels, recommendation, cadence-cycle, active-proposal, protected-window, and hybrid guardrail checks.
4. **[Repository-verified]** Effective after migration 028, `refresh_schedule_proposals` creates `Pending` proposals only for posts with no evaluation timestamp and no proposal history, within its start-date/horizon filter and protected window. A successful insert marks the post evaluated.
5. **[Handoff-only]** `Supabase – Refresh Schedule Proposals` normally runs around 3:10 AM, followed by `Supabase to Google Sheets – Schedule Approvals` around 3:20 AM.
6. **[Handoff-only]** An operator chooses `Approved` or `Rejected` in Sheets; `Google Sheets to Supabase – Schedule Decisions` writes that decision.
7. **[Repository-verified]** `set_schedule_proposal_decision` allows `Pending`, `Approved`, or `Rejected` for any proposal not already `Applied`.
8. **[Repository-verified]** `approved_schedule_changes_ready_to_apply` exposes only approved, unapplied, error-free proposals for posts still synchronized as `scheduled`, and requires the proposed UTC time to remain outside the configured protected window.
9. **[Handoff-only]** `Supabase to Buffer – Apply Approved Schedules` runs approximately 5–10 minutes after the decisions scenario and applies the change to Buffer.
10. **[Repository-verified]** External automation can record success with `mark_schedule_proposal_applied` or failure with `mark_schedule_proposal_error`.
11. **[Live verification required]** The exact Buffer update, stale-schedule comparison, collision recheck, retries, error recovery, and final 12-post regression result.

## Make scenario dependency and timing map

The repository does not contain Make blueprints. The following scenario names and times are therefore operational claims, not repository-verified configuration.

| Flow | Scenario | Predecessor | Handoff timing/relationship | Verification need |
| --- | --- | --- | --- | --- |
| Ingestion | `Buffer to Supabase – Post Sync` | Buffer | **[Handoff-only]** Active; exact cadence unstated | Schedule, filters, pagination, RPC mapping |
| Ingestion | `Buffer to Supabase – Daily Metrics` | Buffer post availability | **[Handoff-only]** Active daily | Schedule, metric mapping, retry behavior |
| Label export | `Supabase to Google Sheets – Label Queue` | Post sync | **[Handoff-only]** Active | Query, marking order, duplicate recovery |
| Label import | `Google Sheets to Supabase – Process Labels` | Operator sets Ready | **[Handoff-only]** Active | Polling cadence, status/error transitions |
| Proposal generation | `Supabase – Refresh Schedule Proposals` | Synced, labeled, eligible posts | **[Handoff-only]** About 3:10 AM | Exact arguments, timezone, run duration, retries |
| Proposal export | `Supabase to Google Sheets – Schedule Approvals` | Proposal refresh | **[Handoff-only]** About 3:20 AM | Exact delay, export/mark atomicity |
| Decision import | `Google Sheets to Supabase – Schedule Decisions` | Operator decision | **[Handoff-only]** Runs before Buffer application | Exact schedule and row matching |
| Buffer application | `Supabase to Buffer – Apply Approved Schedules` | Decision import | **[Handoff-only]** About 5–10 minutes later | Schedule, stale/collision checks, callbacks |

**[Inference]** Staggering reduces the likelihood of downstream reads occurring before upstream writes complete, but elapsed-time staggering alone is not a transactional dependency or completion guarantee.

## Architecture invariants and boundaries

- **[Repository-verified]** Proposal generation does not call Buffer.
- **[Repository-verified]** The application queue requires `Approved` status.
- **[Repository-verified]** Standard anonymous and authenticated roles are denied the mutation RPCs defined by the migrations; `service_role` is granted execution.
- **[Repository-verified]** Time proposals are stored in both local timestamp and `timestamptz` UTC-equivalent form with an accompanying timezone name.
- **[Repository-verified]** Core tables have RLS enabled, but migrations 001–028 define no policies.
- **[Inference]** A web app cannot safely use the current service-only database surface directly from a browser. Authentication, authorization, and server-side mutation boundaries must be designed and verified before implementation.
- **[Live verification required]** Effective production privileges may differ because out-of-repository policies, grants, or manual SQL changes could exist.

## Production-reference principle

**[Handoff-only]** The working Buffer + Make + Supabase + Sheets pipeline should remain operational while an interface is added incrementally.

**[Inference]** The safest first application phase is a read-heavy interface over verified views plus narrowly mediated calls to existing RPCs. It should be compared against the existing Sheets/Make outputs before any workflow is retired.
