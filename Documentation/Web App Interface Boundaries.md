# Web App Interface Boundaries

## Purpose and non-goals

This document identifies safe initial page boundaries and candidate existing database surfaces. It does not design, scaffold, or implement a web application.

- **[Repository-verified]** Directly supported by migrations 001–028.
- **[Handoff-only]** Supplied only by the handoff.
- **[Inference]** Proposed boundary derived from the current backend.
- **[Live verification required]** Requires production artifacts or operator confirmation.

**[Handoff-only]** The intended first application should replace the human interface incrementally while retaining Supabase as the backend, Buffer as publisher, and Make as initial automation/orchestration.

**[Inference]** The initial application should be an additional interface over the reference workflow, not a parallel scheduling engine.

## Access-model prerequisite

**[Repository-verified]** Migrations enable RLS on core operational tables but define no RLS policies. Mutation RPCs are generally revoked from `anon` and `authenticated` and granted to `service_role`. The Looker login role is read-only but migration 012 grants it internal reporting views in addition to curated ones.

**[Repository-verified]** The repository defines no authenticated web-app roles, tenancy rules, user identities, authorization policies, or browser-safe API boundary.

**[Inference]** The web app must not embed a service-role credential in browser code. Before implementation, choose and document a server-side mediation/auth model, least-privilege grants, and RLS policies or equivalent authorization controls.

**[Live verification required]** Current Supabase Auth usage, manually created policies, roles, grants, function ownership, and deployment topology.

## Proposed page map

| Page | Initial responsibility | Candidate existing read surfaces | Candidate existing mutations | Important boundary |
| --- | --- | --- | --- | --- |
| Dashboard | High-level performance, recent results, platform comparison, data freshness | `looker_dashboard_posts`, `looker_daily_growth`, `looker_posting_time_summary`, `looker_content_performance_summary` | None initially | Do not reproduce metric ingestion or recommendation logic in UI code. |
| Upcoming Posts | Scheduled posts, local/UTC due time, label/evaluation state, proposal presence | `dashboard_posts` or a future curated wrapper; `looker_schedule_change_proposals`; content-aware preview as diagnostic | None initially | The existing broad views may expose more fields than a UI needs; create least-privilege wrappers only in a separately approved backend phase. |
| Label Queue | Unlabeled export-ready work, labels, shared Clip Group membership, processing status | `pending_label_queue_exports`, `unlabeled_posts_queue`, `dashboard_posts` | Mediated `process_content_label_payload`; possibly `mark_label_queue_exported` only while Make remains exporter | Database does not store `Unlabeled/Ready/Processed`; app lifecycle must not be invented without Sheet/Make confirmation. Shared edits affect all linked posts. |
| Schedule Approvals | Pending proposals, rationale, current/proposed time, approve/reject, application result | `looker_schedule_change_proposals`; `pending_schedule_proposal_exports`; content-aware proposal preview for explanation | Mediated `set_schedule_proposal_decision` | UI must never apply Buffer directly during the interface-only phase. Approval and application remain distinct. |
| Analytics | Posting-time, content, recommendation hierarchy, confidence, fallback, freshness | Posting/content summaries; day/window/joint recommendation views; content-aware recommendation and fallback views | None initially | Clearly label small samples, stale metrics, and fallback level. Do not present correlation as guaranteed lift. |
| System/Error Status | Sync freshness, proposal errors, workflow lag, audit references | `automation_runs` if actually populated; proposal error/result fields; latest sync/capture timestamps; preview summaries | None initially | Repository does not prove `automation_runs` is used. Make run/error data needs an integration or sanitized export. |

## Dashboard page

### Candidate repository surfaces

- **[Repository-verified]** `looker_dashboard_posts` provides one post row with latest metrics and labels.
- **[Repository-verified]** `looker_daily_growth` provides daily metric deltas after the first snapshot.
- **[Repository-verified]** `looker_posting_time_summary` and `looker_content_performance_summary` provide rollups.

### Boundary recommendation

**[Inference]** Start read-only and match the existing Looker calculations before adding new calculations. Treat repository-defined `calculated_interaction_rate` and Buffer `engagement_rate` as separate measures.

**[Handoff-only]** Existing Looker surfaces include total views, average views, TikTok/YouTube comparison, recent performance, content-type performance, posting-time performance, and labeled-content performance.

**[Live verification required]** Looker report inventory, calculated fields, filters, date dimensions, credential mode, and refresh cadence.

## Upcoming Posts page

### Candidate repository surfaces

- **[Repository-verified]** `dashboard_posts` contains synchronized status and current due time plus local timezone conversion.
- **[Repository-verified]** `looker_schedule_change_proposals` shows proposal history and status.
- **[Repository-verified]** `looker_content_aware_proposal_preview` exposes diagnostic readiness and blocking reasons.

### Boundary recommendation

**[Inference]** Show Buffer-synchronized schedule separately from proposal state. Never imply that a proposed or Applied audit row proves Buffer’s current live schedule without a sufficiently recent post sync.

**[Live verification required]** Buffer sync cadence, cancellation/deletion semantics, and whether Applied results are reconciled to a subsequent post sync.

## Label Queue page

### Candidate repository surfaces and actions

- **[Repository-verified]** `pending_label_queue_exports` identifies posts that have neither content linkage nor export timestamp.
- **[Repository-verified]** `unlabeled_posts_queue` identifies all posts without content linkage, regardless of export state.
- **[Repository-verified]** `process_content_label_payload` is the current JSON mutation boundary.

### Boundary recommendation

**[Inference]** During coexistence, select one owner for queue export/claiming to avoid the app and Make racing to mark rows exported. The app could initially read the same queue without taking over export tracking.

**[Repository-verified]** The exact `Unlabeled → Ready → Processed` state machine is not represented in database columns.

**[Inference]** Before editing an existing Clip Group, show all linked posts and make the shared effect explicit. A row-level mental model would be misleading because labels belong to `content_items`, not individual posts.

**[Live verification required]** Sheet status/error workflow and whether reprocessing/corrections are allowed.

## Schedule Approvals page

### Candidate repository surfaces and actions

- **[Repository-verified]** `looker_schedule_change_proposals` exposes current/proposed schedules, recommendation evidence, decision status, result, and errors.
- **[Repository-verified]** `set_schedule_proposal_decision(uuid, text)` is the existing decision mutation.
- **[Repository-verified]** `approved_schedule_changes_ready_to_apply` is the service-only application queue, not a browser data source.

### Boundary recommendation

**[Inference]** The first app should record decisions through a server-side mediator while the existing Make application scenario remains the only Buffer-changing component. The interface should distinguish:

- recommendation generated;
- exported/presented;
- approved or rejected;
- eligible for application;
- applied or errored;
- verified by later Buffer post sync.

**[Repository-verified]** Application eligibility rechecks status, synchronized scheduled state, error/application state, and proposed protected window. It does not independently recheck collisions or stale Buffer current schedule.

**[Live verification required]** Make row matching, decision schedule, last-mile checks, and partial failure recovery.

## Analytics page

### Candidate repository surfaces

- platform day, time-window, and joint recommendations;
- content-aware group recommendations and summaries;
- fallback preview;
- cadence settings and weekly slot plan;
- content performance and posting-time rollups.

All listed surfaces are **[Repository-verified]** SQL views.

### Boundary recommendation

**[Inference]** Present model level, threshold, group sample, slot sample, confidence, metric age/status, and fallback reason together. A score without those fields would overstate certainty.

**[Inference]** Mark `Experimental` as limited evidence, not failure. Keep platform fallback visible so operators can see when the content-specific hierarchy did not qualify.

## System/Error Status page

### Candidate repository surfaces

- **[Repository-verified]** Post `last_synced_at`, latest metric capture/update dates, proposal `Error` rows, and result/error fields can support basic database-side health indicators.
- **[Repository-verified]** `automation_runs` exists but no inspected migration writes to it.
- **[Repository-verified]** Preview summary views expose blocked versus ready proposal counts, not external scenario health.

### Boundary recommendation

**[Inference]** Do not label the system healthy solely because the database queue is empty. Empty can mean no work, stale ingestion, a failed upstream scenario, or successful completion.

**[Live verification required]** Make run history/error endpoints, expected freshness thresholds, Buffer update logs, Sheet processing errors, and alert ownership.

## Reporting surfaces for initial reuse

**[Repository-verified]** The following curated families are candidates for read-only UI use after access review:

- post/metric: `looker_dashboard_posts`, `looker_daily_growth`;
- performance rollups: `looker_posting_time_summary`, `looker_content_performance_summary`;
- platform recommendations: `looker_posting_day_recommendations`, `looker_time_window_recommendations`, `looker_posting_recommendation_summary`, `looker_joint_posting_recommendations`, `looker_joint_posting_recommendation_summary`;
- cadence: `looker_scheduling_cadence_settings`, `looker_weekly_slot_plan`;
- proposal audit: `looker_schedule_change_proposals`;
- content-aware diagnostics: recommendation, fallback, shadow, hybrid, proposal-preview, and corresponding summary views.

**[Inference]** “Looker” naming does not make a view automatically suitable for authenticated application clients. Field exposure, ownership semantics, performance, and authorization need review.

## Initial mutation boundaries

**[Inference]** If approved in a future phase, the narrowest initial operator mutations are:

- process a label payload;
- approve or reject a proposal.

These should be server-mediated and audited. The interface-only phase should not:

- call Buffer directly;
- execute migrations;
- invoke proposal refresh automatically from a browser;
- mark proposals Applied/Error without performing the external operation;
- change cadence settings;
- replace Make export/application scenarios;
- expose the service-role key.

## Coexistence rules

1. **[Inference]** Keep Make/Supabase/Sheets/Buffer/Looker operational while the app is validated.
2. **[Inference]** Define single-writer ownership per action during transition.
3. **[Inference]** Compare app reads and decisions with the existing sheet/report outputs using the same IDs and timestamps.
4. **[Inference]** Preserve proposal and application history; do not “clean up” old rows for presentation.
5. **[Inference]** Do not change scheduling algorithms while validating the interface.
6. **[Inference]** Treat differences as investigation items, not permission to silently normalize production data.

## Required decisions before implementation

- **[Live verification required]** Auth provider and authorized operator identities.
- **[Live verification required]** Server/backend deployment model and secret storage.
- **[Live verification required]** Supabase RLS/grant design for authenticated app access.
- **[Live verification required]** Whether the app or Make owns queue claiming and decision writes during coexistence.
- **[Live verification required]** Sanitized Google Sheets schemas and Make scenario contracts.
- **[Live verification required]** Exact Looker calculations to reproduce.
- **[Live verification required]** Expected stale-schedule and collision behavior before Buffer application.
- **[Live verification required]** Final 12-post regression result.
