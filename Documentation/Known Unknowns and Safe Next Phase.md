# Known Unknowns and Safe Next Phase

## Evidence labels

- **[Repository-verified]** Directly supported by inspected repository files.
- **[Handoff-only]** Supplied only by the handoff document.
- **[Inference]** Proposed interpretation or next-phase recommendation.
- **[Live verification required]** Requires sanitized live-system evidence or operator confirmation.

## Current confidence boundary

**[Repository-verified]** Migrations 001–028 define a coherent database-side ingestion, labeling, analytics, recommendation, approval, and application-handoff model. Effective proposal generation after migration 028 is separately documented from historical definitions.

**[Handoff-only]** Make, Google Sheets, Buffer, and Looker form the working production workflow and should remain the reference implementation.

**[Live verification required]** The repository alone cannot prove that live Supabase matches the migrations, that Make uses the intended functions/views, that Sheet workflows match the handoff, or that Buffer application behavior is safe under retries and stale state.

## Known unknowns register

| Area | What is known | Unknown requiring verification | Risk if assumed |
| --- | --- | --- | --- |
| Applied schema | **[Repository-verified]** Intended migration sequence is 001–028. | Applied migration ledger, drift, live function definitions, ownership, constraints, policies, and grants. | App can target nonexistent or differently secured objects. |
| Reporting permissions | **[Repository-verified]** Migration 012 broadens reader access after 011 narrowed it. | Actual live grants and whether broad access is intentional. | Excess data exposure or broken reporting after “cleanup.” |
| RLS/auth | **[Repository-verified]** RLS enabled; no policies or authenticated app model in migrations. | Manual policies, Supabase Auth use, operator identities, tenant expectations. | Unsafe service-role exposure or inaccessible app. |
| Buffer post sync | **[Repository-verified]** RPC input and upsert behavior. | Make query, paging, status coverage, deletion handling, retries, cadence. | Missing/stale upcoming posts and misleading UI state. |
| Buffer metrics | **[Repository-verified]** Daily Denver snapshot upsert and recognized metrics. | API availability/lag by platform, paging, retry, capture schedule. | Incorrect freshness or performance comparisons. |
| Label Queue states | **[Repository-verified]** Database has content linkage and export timestamp, not sheet states. | Exact `Unlabeled/Ready/Processed` machine, errors, corrections, validations. | App invents incompatible workflow states. |
| Shared Clip Group | **[Repository-verified]** Shared item updates affect all linked posts. | Operator intent for conflicting row labels and corrections. | Silent cross-platform label changes. |
| Cadence gap | **[Repository-verified]** TikTok = 6 hours; YouTube short form = 4 hours despite six-hour prose. | Which YouTube gap is intended/live. | Changed cadence or unexpected collisions. |
| One-time evaluation | **[Repository-verified]** After 028, inserted/history posts are protected; no-op/blocked rows may be reconsidered. | Product intent for no-op and temporarily blocked rows. | Documentation or UI overstates finality. |
| Proposal uniqueness | **[Repository-verified]** Active uniqueness is a partial index; all-history blocking exists only in two functions. | Other insert paths, manual SQL, future repeat-cycle intent. | Duplicate history can reappear through bypass paths. |
| Collision safety | **[Repository-verified]** Generation-time hybrid checks; no application-view recomputation. | Make/Buffer last-mile collision checks. | Approved update collides with later schedule changes. |
| Stale schedule | **[Repository-verified]** Application-ready view does not compare captured current time to live/current synchronized due time. | Conditional update or Make preflight behavior. | Overwrite of an operator’s later Buffer change. |
| Preview calendar | **[Repository-verified]** Fixed local +2 to +23 upstream calendar, then RPC date filter. | Exact Make date arguments and intended flexibility. | Missing proposals for requested ranges. |
| Timezone | **[Repository-verified]** Named timezone conversions and Denver defaults. | Database/session, Make, Sheet, Buffer settings and DST behavior. | Day/date shifts or ambiguous local times. |
| Proposal application | **[Repository-verified]** Approved queue and success/error callbacks. | Exact Buffer mutation, retry/idempotency, partial failure reconciliation. | Buffer and Supabase audit diverge. |
| Make timing | **[Handoff-only]** Approximate 3:10/3:20 and 5–10 minute staggering. | Actual schedules, completion dependencies, concurrency, retries. | Downstream scenario races or stale reads. |
| Looker | **[Repository-verified]** Reporting views exist. **[Handoff-only]** Named dashboard topics are used. | Active data sources, pages, calculations, filters, refresh/credential mode. | App metrics disagree with production reports. |
| Automation health | **[Repository-verified]** `automation_runs` exists with no repository writer. | Whether it is populated; Make health/error data availability. | False “healthy” system status. |
| Migration 028 results | **[Handoff-only]** Reported cleanup and fresh-proposal counts. | Sanitized live validation queries/results. | Defect considered fixed without evidence. |
| Twelve-post regression | **[Handoff-only]** 12 proposals were generated and approved. | Final application, errors, Buffer match, later zero-duplicate refresh. | Unproven baseline frozen as known-good. |

## Additional artifacts required

All artifacts must be sanitized. Do not provide credentials, tokens, API keys, connection strings, private payload bodies, backups, private exports, or unnecessary personal data.

### Make

**[Live verification required]** Provide sanitized blueprints or configuration screenshots for:

- `Buffer to Supabase – Daily Metrics`;
- `Buffer to Supabase – Post Sync`;
- `Google Sheets to Supabase – Process Labels`;
- `Google Sheets to Supabase – Schedule Decisions`;
- `Supabase – Refresh Schedule Proposals`;
- `Supabase to Buffer – Apply Approved Schedules`;
- `Supabase to Google Sheets – Label Queue`;
- `Supabase to Google Sheets – Schedule Approvals`.

Include schedules/timezones, module sequence, RPC/view names, field mapping, filters, pagination, retries, error routes, concurrency, row keys, and how downstream scenarios know upstream work completed. Replace secrets and personal payload data with explicit placeholders.

### Supabase

**[Live verification required]** Provide:

- applied migration ledger;
- schema-only catalog of tables, columns, constraints, indexes, views, functions/signatures/owners, triggers, grants, and RLS policies;
- database and relevant role timezone settings;
- sanitized role memberships and view/function ownership;
- sanitized migration-028 verification counts and function-definition hashes or text;
- isolated/test-environment results for regression conditions.

No data backup or production row export is required for the architecture phase.

### Google Sheets

**[Live verification required]** Provide sanitized structural exports or screenshots for Label Queue and Schedule Approvals:

- column names/order and data types;
- validation values and exact statuses;
- formulas and protected ranges;
- stable keys used by Make;
- success/error/retry state behavior;
- timezones and date formatting;
- how edits to already processed/shared Clip Groups are handled.

Use representative synthetic rows rather than private content data where possible.

### Buffer

**[Live verification required]** Provide sanitized API contract examples or vendor documentation references for:

- post list/status/due-time fields;
- metrics fields and freshness;
- schedule-update request and response;
- idempotency or conditional update capability;
- stale update and collision behavior;
- rate limits and retry guidance;
- current channel timezone/queue settings without secrets.

Also provide the final sanitized 12-post regression outcome.

### Looker Studio

**[Live verification required]** Provide:

- report/page inventory;
- data-source-to-Supabase-view map;
- calculated fields and aggregation definitions;
- filters, date dimensions, timezone behavior, and refresh cadence;
- credential mode and the minimum database privileges actually required.

## Safe next-phase plan

The phases below add an interface without replacing the working backend. They are planning boundaries, not authorization to implement.

### Phase 0: Verify and freeze the reference baseline

**[Inference]** Before application work:

1. obtain the sanitized artifacts above;
2. verify live schema/function/grant drift against migrations 001–028;
3. resolve or explicitly accept the migration-012 reporting access and YouTube gap discrepancies;
4. complete and record the 12-post regression outcome;
5. document operator recovery steps for failed sync, export, decision, and Buffer application;
6. capture baseline output examples from Sheets and Looker using synthetic or minimally necessary data.

**Exit gate:** **[Live verification required]** The production workflow is demonstrably known-good, and unresolved deviations have named owners and accepted risks.

### Phase 1: Define security and contracts

**[Inference]** Specify:

- user authentication and authorized operator roles;
- server-side boundary for privileged RPCs;
- RLS policies or equivalent least-privilege authorization;
- curated, minimal application read models;
- typed contracts for current views/RPCs;
- audit/event correlation IDs across app, Make, Supabase, and Buffer where feasible;
- single-writer ownership during coexistence.

Do not expose service-role credentials to a browser. Do not repurpose the Looker login role as an application identity without an explicit security review.

**Exit gate:** Threat model, access matrix, data contracts, and rollback/disable plan are reviewed.

### Phase 2: Read-only interface parity

**[Inference]** Build only after separate approval. Initial read-only pages should be:

- Dashboard;
- Upcoming Posts;
- Label Queue observation;
- Schedule Approval observation;
- Analytics;
- System/Error Status with clearly bounded signals.

Compare displayed values against current Looker and Sheets outputs. Retain provenance labels for synchronized, proposed, approved, applied, and verified-live states.

**Exit gate:** Defined parity checks pass without modifying production workflows.

### Phase 3: Human labeling interface in coexistence

**[Inference]** Introduce server-mediated labeling using the existing payload RPC only after the exact Sheet state machine is verified. Show all posts linked to a Clip Group before shared edits. Choose either app or Make as queue claimant/writer for each row to prevent duplicate processing.

Keep Sheets available as fallback until correction, retry, and audit cases pass.

**Exit gate:** New and shared Clip Group tests match existing behavior, including failures and operator corrections.

### Phase 4: Approval interface in coexistence

**[Inference]** Add server-mediated Pending/Approved/Rejected decisions using the existing decision RPC. Leave proposal generation and Buffer application in Make. The app must not equate Approved with Applied.

Test duplicate clicks, stale pages, concurrent Sheet/app decisions, protected-window expiry, and error display.

**Exit gate:** Decision and audit results match the reference workflow, with a tested disable/fallback path.

### Phase 5: Harden application preflight before replacing anything

**[Inference]** Decide, test, and document where to revalidate:

- current Buffer due time against proposal baseline;
- same-platform collisions at application time;
- current protected window;
- current post status;
- timezone/channel changes;
- idempotency and partial failure.

This may be implemented in existing Make or a future server component, but not silently split across both.

**Exit gate:** Repeatable stale/collision/idempotency tests pass in a non-production or controlled environment.

### Phase 6: Replace workflows individually, if justified

**[Inference]** Candidate replacement order should follow observed operational value and risk, not convenience. For each scenario:

1. document its exact contract;
2. run the replacement in shadow/read-only mode where possible;
3. compare results and failure handling;
4. switch one writer at a time;
5. retain rollback;
6. observe before retiring the old scenario.

Avoid a one-shot replacement of Make, Sheets, Buffer integration, recommendation SQL, and reporting.

## System invariants for every future phase

- Manual approval remains required before any Buffer schedule change.
- The configured protected window is checked again immediately before application.
- Same-platform collision/day-limit rules are revalidated against current state before application.
- A proposal never hides or overwrites audit history.
- One active Pending/Approved proposal per post remains database-enforced.
- Any-proposal-history protection remains in every authorized proposal-creation path unless the product explicitly adopts repeat cycles.
- Shared Clip Group edits disclose their multi-post effect.
- Local and UTC timestamps plus timezone name remain visible and testable.
- The app distinguishes synchronized data from live-verified external state.
- Working production components remain until their replacements pass parity, failure, rollback, and operator-acceptance checks.

The first eight items are **[Inference]** requirements derived from repository guardrails; active-proposal uniqueness and existing timestamp storage are also **[Repository-verified]** current behavior.

## Explicitly deferred work

The following are outside this documentation phase:

- web application selection, design, scaffolding, or implementation;
- migration rewrites or new database objects;
- changes to Make, Buffer, Sheets, Supabase, or Looker;
- AI-assisted labeling design;
- replacing the content-aware scoring/scheduler;
- changing cadence settings;
- granting application access.
