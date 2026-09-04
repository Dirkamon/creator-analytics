# Web App Interface Boundaries

## Purpose and non-goals

This document records the original interface boundaries and the additive least-privilege read model implemented for the Phase 1 application. It does not authorize deployment or any production database change.

- **[Repository-verified]** Directly supported by migrations 001–028.
- **[Handoff-only]** Supplied only by the handoff.
- **[Inference]** Proposed boundary derived from the current backend.
- **[Live verification required]** Requires production artifacts or operator confirmation.

**[Handoff-only]** The intended first application should replace the human interface incrementally while retaining Supabase as the backend, Buffer as publisher, and Make as initial automation/orchestration.

**[Inference]** The initial application should be an additional interface over the reference workflow, not a parallel scheduling engine.

## Access-model prerequisite

**[Repository-verified]** Migrations enable RLS on core operational tables but define no RLS policies. Mutation RPCs are generally revoked from `anon` and `authenticated` and granted to `service_role`. The Looker login role is read-only but migration 012 grants it internal reporting views in addition to curated ones.

**[Repository-verified]** Migrations 001–032 define no authenticated web-app role or browser-safe application data boundary. Migration 033 additively defines a restricted server-only reader, a no-login projection owner, a private `creator_app` schema, and exact application projections. Private fixed-search-path helpers preserve the existing public-view ACLs and `posts` RLS state where nested security-invoker views cannot be safely projected through direct grants.

**[Repository-verified]** The implemented application keeps Supabase Auth in the browser/SSR boundary and performs data reads through the server-only `creator_analytics_web_reader` only after server-side session and email-allowlist authorization. The query compiler uses closed relation/column/filter/order allowlists and parameterizes values.

**[Repository-verified]** Migration 035 adds a separate `creator_analytics_web_labeler` login and one audited SECURITY DEFINER wrapper. Migration 036 adds durable Make claim state and a trigger beneath every labeling path. The role has no direct table access. An app-labeled row cannot be claimed by Make, and a Make-claimed row cannot be linked by the app.

**[Repository-verified]** `PUBLIC`, `anon`, `authenticated`, `service_role`, and `creator_dashboard_reader` have no access to `creator_app`. The web reader has `SELECT` only on the 16 application projections plus `EXECUTE` on six private read helpers whose return columns exactly match their projections; it has no direct access to public source views or tables. The view owner cannot log in.

**[Inference]** `creator_app` should remain outside the Supabase Data API exposed-schema configuration. This provides defense in depth; browser-direct data access is not part of the architecture.

**[Live verification required]** Migration-033 deployment, role-password provisioning, custom-role pooler connection format, verified TLS behavior, current Supabase Auth users/settings, production secret storage, and hosting topology.

## Proposed page map

| Page                | Initial responsibility                                                                  | Candidate existing read surfaces                                                                                         | Candidate existing mutations                                                                         | Important boundary                                                                                                 |
| ------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Dashboard           | High-level performance, recent results, platform comparison, data freshness             | `looker_dashboard_posts`, `looker_daily_growth`, `looker_posting_time_summary`, `looker_content_performance_summary`     | None initially                                                                                       | Do not reproduce metric ingestion or recommendation logic in UI code.                                              |
| Upcoming Posts      | Scheduled posts, local/UTC due time, label/evaluation state, proposal presence          | `creator_app.dashboard_posts`; `creator_app.looker_schedule_change_proposals`                                            | None                                                                                                 | Exact projections omit channel IDs, raw payloads, and operational columns the page does not use.                   |
| Label Queue         | Unlabeled export-ready work, labels, shared Clip Group membership, processing status    | `creator_app.pending_label_queue_exports`, `unlabeled_posts_queue`, `dashboard_posts`                                    | Staging-only web wrapper; Make-only atomic claim/finalize functions                                  | App writes are rejected after Make claims. Existing-group mode links the post without changing shared labels.      |
| Schedule Approvals  | Pending proposals, rationale, current/proposed time, approve/reject, application result | `looker_schedule_change_proposals`; `pending_schedule_proposal_exports`; content-aware proposal preview for explanation  | Mediated `set_schedule_proposal_decision`                                                            | UI must never apply Buffer directly during the interface-only phase. Approval and application remain distinct.     |
| Analytics           | Posting-time, content, recommendation hierarchy, confidence, fallback, freshness        | Posting/content summaries; day/window/joint recommendation views; content-aware recommendation and fallback views        | None initially                                                                                       | Clearly label small samples, stale metrics, and fallback level. Do not present correlation as guaranteed lift.     |
| System/Error Status | Sync freshness, proposal errors, workflow lag, audit references                         | `automation_runs` if actually populated; proposal error/result fields; latest sync/capture timestamps; preview summaries | None initially                                                                                       | Repository does not prove `automation_runs` is used. Make run/error data needs an integration or sanitized export. |

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
- **[Repository-verified]** `process_content_label_payload` remains the internal JSON mutation boundary. Migration 035 adds `process_content_label_payload_for_web` as the only application mutation boundary for labeling.

### Boundary recommendation

**[Repository-verified]** During coexistence, ownership is selected atomically per row. Make calls `claim_pending_label_queue_exports`, which locks eligible rows and stores an opaque token before returning them. The web app can label only unclaimed rows. Make finalizes only by presenting the exact token to `mark_label_queue_exported(post_id, claim_token)`. The app never writes claim or export state.

**[Repository-verified]** Migration 036 revokes `service_role` access to the former direct queue read and one-argument marker, so a stale Make scenario fails closed. Claims are not automatically released because the database cannot know whether an external Sheet write succeeded before finalization.

**[Live verification required]** Staging must prove the updated Make mapping, wrong-token and duplicate-finalize behavior, and manual review procedure for interrupted claims before any production decision.

**[Repository-verified]** The exact `Unlabeled → Ready → Processed` state machine is not represented in database columns.

**[Repository-verified]** Linking an existing Clip Group shows its current labels and linked-platform count, requires explicit shared-effect confirmation, and changes only the selected post link. Existing shared labels are never overwritten by this mode.

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

**[Repository-verified]** “Looker” naming does not make a public view a browser-facing contract. Migration 033 projects only the fields currently used by the app into the private `creator_app` schema; the authenticated browser roles do not receive access.

## Migration-033 trust boundary

**[Repository-verified]** Authentication and data access are deliberately separate:

1. The browser uses the publishable key for magic-link Auth and SSR session cookies.
2. The protected-route proxy performs an optimistic session-presence check.
3. Every server data query validates the user with Supabase Auth and checks the environment allowlist.
4. Only after authorization succeeds does the server lazily acquire the restricted PostgreSQL client.
5. The compiler accepts only repository-defined query specifications and parameterizes all values.
6. PostgreSQL independently limits the login to the `creator_app` projections and read-only defaults.

**[Repository-verified]** This model does not grant application access to mutation functions, tables, existing public views, Make-facing service surfaces beyond the single projected proposal ID, or the public 19-column Make contract.

**[Live verification required]** A staging deployment must prove that the role can connect through the selected Supabase pooler, that no direct or inherited grants broaden access, and that `creator_app` is not exposed through the Data API.

## Migration-035/036 labeling trust boundary

**[Repository-verified]** Authentication, reading, and labeling use separate layers:

1. The normal protected-route authorization still validates the Supabase Auth user and server-side email allowlist.
2. Read data still uses `creator_analytics_web_reader` and the closed query compiler.
3. Label submissions are validated against the exact Google Sheets `Lists` vocabulary before a separate server-only labeler client is acquired.
4. The labeler calls one fixed function signature and cannot read or mutate tables directly.
5. PostgreSQL locks the post and normalized Clip Group, rechecks linkage/claim/export ownership, preserves existing group labels, performs the write, and records the authorized email atomically.
6. Make can obtain export rows only through an atomic claim. Finalization requires the exact row token, while a trigger blocks every content-link path until that claim is finalized.
7. A case-insensitive unique index prevents a display-case variation from creating a second logical Clip Group.

**[Repository-verified]** The application flag defaults off and the configuration parser refuses to enable it unless the application origin is loopback or contains `staging`. A separate encrypted writer URL is required; the reader credential cannot satisfy that configuration.

**[Live verification required]** Staging must prove the custom-role pooler login, write audit, both ownership-race directions, exact-token finalization, interrupted-claim review, shared-group confirmation, fallback processing, disable switch, and absence of credential details in browser assets and logs before any production decision.

## Initial mutation boundaries

The narrowest operator mutations are:

- **[Repository-verified]** process a label payload through the controlled migration-035 staging path;
- **[Inference]** approve or reject a proposal in a later, separately reviewed phase.

Both should be server-mediated and audited. The current controlled-labeling phase does not:

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
