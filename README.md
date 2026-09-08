# Creator Analytics

A personal analytics and content operations project for gaming short-form video, focused on TikTok and YouTube Shorts. It brings post history, performance metrics, content labels, and proposed publishing schedules into a shared data model, with human approval before schedule changes.

The project connects a practical creator workflow to technical product concerns: defining useful metrics, translating operating rules into software, integrating external services, and introducing new interfaces without disrupting existing processes.

## Problem and purpose

Publishing the same clip across platforms creates fragmented records: performance lives in analytics tools, schedules live in Buffer, and content context often depends on manual tracking. Comparing clips and deciding what to publish next requires those records to agree.

Creator Analytics is designed to make that work more consistent by:

- Connecting platform posts to a shared Clip Group and content labels.
- Preserving daily performance snapshots for reporting and comparison.
- Turning historical posting-time and content performance into reviewable schedule proposals.
- Tracking proposals through decisions, application results, and errors.

## Architecture and stack

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Publishing integration | Buffer API | Source of post, schedule, and metric data; destination for approved schedule updates. |
| Workflow orchestration | Make.com | Coordinates ingestion, Sheet exchanges, and schedule application in the documented operating workflow. |
| Data and business logic | Supabase / PostgreSQL, SQL migrations | Stores posts and snapshots; implements labeling, reporting, recommendation logic, and proposal guardrails. |
| Operator workflow | Google Sheets | Label Queue and Schedule Approvals interface for the established automation workflow. |
| Reporting | Looker Studio | Consumes dedicated reporting views. |
| Web interface | Next.js, React, TypeScript, Tailwind CSS, Supabase Auth | Private operator pages over restricted server-side database access; documented production host is on Vercel. |
| Verification | SQL regression scripts, Vitest, Testing Library, Playwright | Database regression coverage, unit/component tests, and a sign-in smoke test. |

The documented flow is **Buffer → Make → Supabase → reporting and operator review**. Approved schedule changes return to Buffer through Make. The web app reads curated database projections and has a separately gated labeling path; it does not run ingestion, generate or approve proposals, or apply Buffer schedule changes.

## Key capabilities

- **Performance reporting:** dashboard, top posts, platform and game filters, daily growth, content comparisons, and posting-time summaries.
- **Content organization:** game, content type, vibe, and other labels, with shared Clip Groups linking versions of a clip across platforms.
- **Schedule recommendations:** SQL-based scoring uses content-specific history where eligible and falls back to broader platform performance. Proposals expose supporting samples, scores, and confidence indicators for review.
- **Operational visibility:** upcoming posts, label queue state, proposal decisions and application errors, plus database-observed freshness.
- **Controlled web labeling:** an optional, disabled-by-default write path with a separate database identity, validation, operator audit records, and export ownership checks.

## Technical highlights

**A durable data model.** Post ingestion upserts by Buffer post ID, while daily metrics use a unique post/date key. Repeated same-day metric ingestion updates the snapshot rather than adding a duplicate. Shared content records support comparisons across platform versions.

**Explicit scheduling rules.** Cadence settings, minimum gaps, protected publishing windows, local/UTC timestamps, and proposal history constrain scheduling. Migration 029 adds same-channel reservation checks during generation and before proposals are exposed for application, using synchronized database state.

**Stable integration contracts.** Later migrations preserve existing reporting and Make-facing interfaces while adding collision checks, restricting permissions, and optimizing proposal generation. This supports incremental change across connected systems.

**Clear ownership during interface changes.** Migrations 035–036 separate web labeling from the Sheets fallback. Atomic export claims prevent the app and exporter from taking the same row; finalization requires the matching claim token.

## Reliability and security practices

- Manual approval is required before a proposal enters the schedule-application queue. Proposed, Approved, and Applied are distinct states.
- Proposal history and database uniqueness rules protect against repeat proposals; application timestamps and errors preserve operational context.
- Web access uses Supabase authentication and server-side email allowlist checks before database reads.
- Separate restricted reader and labeler roles limit access. Queries use explicit columns, bounded results, and parameterized values; database credentials stay on the server.
- Production labeling requires an additional explicit gate. The documented rollout includes staging checks and a feature flag to disable labeling.
- SQL regressions and web tests cover behavior and access boundaries. Sanitized fixtures support web tests without production credentials.

**Secrets and credentials are stored outside this repository.** Environment files and key files are ignored, and committed configuration examples use placeholders. See the [web app setup guide](apps/web/README.md) for credential provisioning and verified-TLS requirements.

System Status reports what the database has observed; it does not establish live Buffer, Make, or Google Sheets health. External retries, partial failures, and deployed configuration require operational verification.

## Current status

The repository contains database migrations **001–036** and a private web application with Dashboard, Top Posts, Upcoming Posts, Label Queue, Schedule Approvals, Analytics, and System Status pages.

Project handoff documentation describes the Buffer/Make/Supabase/Sheets/Looker workflow in operational use. The web app defaults to read-only behavior, with controlled labeling available only when its prerequisites and gates are satisfied. Repository contents alone do not confirm which migrations or feature flags are currently enabled in production.

Direct platform analytics integrations, Twitch support, and AI-assisted content analysis remain future ideas in the project plan. The current recommendation approach is based on SQL rules and historical performance; no measured engagement lift or predictive accuracy is claimed.

## Selected project learnings

- **Model the whole lifecycle.** Preventing duplicate active proposals was insufficient once older proposals became Applied. The migration history shows why eligibility also needs historical state.
- **Keep recommendations explainable.** Content-specific samples can be sparse; fallback levels and supporting sample counts help an operator judge a recommendation.
- **Separate a decision from its execution.** Approval does not prove an external update succeeded. Application results and synchronized state need separate tracking.
- **Define ownership before adding another interface.** A web labeler and a Sheet exporter need an explicit claim protocol. Interrupted external writes require review because automatic reclaim could duplicate Sheet rows.
- **Make observability honest.** A recent database timestamp is evidence of a recent observation, not proof that every connected service is healthy.

## Explore the project

- [Web app and access boundaries](apps/web/README.md) — current interface, setup, test commands, and rollout requirements.
- [Database migrations](Database/) and [database regression scripts](Tests/Database/) — data model, scheduling rules, and access controls.
- [Architecture overview](<Documentation/Architecture Overview.md>) — integration responsibilities and evidence boundaries.
- [Labeling and scheduling workflows](<Documentation/Labeling and Scheduling Workflows.md>) — operator lifecycle and database handoffs.
- [Known unknowns and next phases](<Documentation/Known Unknowns and Safe Next Phase.md>) — operational verification needs and phased development.

Some architecture documents retain their original migration-028 scope. Use the later migrations and web app README for subsequent implementation changes.
