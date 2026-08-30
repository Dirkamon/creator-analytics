# Creator Analytics web app

Phase 1 is a private, read-only Next.js interface over the existing Creator Analytics Supabase reporting surfaces. It does not replace or trigger Buffer, Make, Google Sheets, Looker Studio, ingestion, labeling, proposal generation, approval, or schedule application workflows.

## Local configuration

Copy `.env.example` to `.env.local` and replace every placeholder locally. Never commit `.env.local` or paste its contents into logs, screenshots, tests, or documentation.

Required variables:

- `NEXT_PUBLIC_SUPABASE_URL`: browser-safe project URL used by Supabase Auth.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: browser-safe publishable/anon key used only for Auth session handling.
- `CREATOR_ANALYTICS_ALLOWED_EMAILS`: comma-separated approved email addresses. Authorization normalizes case and checks this server-side before every database SELECT.
- `CREATOR_ANALYTICS_APP_ORIGIN`: local application origin used for magic-link callbacks, such as `http://localhost:3000`.
- `CREATOR_ANALYTICS_DATABASE_URL`: server-only PostgreSQL connection URL for the migration-033 `creator_analytics_web_reader` role. Use the Supabase pooler and verified TLS in production.
- `CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS`: database post-sync freshness threshold; defaults to `15` hours to allow for the approximately 12-hour post-sync cadence while remaining configurable.
- `CREATOR_ANALYTICS_METRICS_STALE_HOURS`: database metrics freshness threshold; defaults to `48` hours.

The database URL must never use a `NEXT_PUBLIC_` prefix. It is imported only by a `server-only` module and is not returned in DTOs, HTML, errors, logs, screenshots, fixtures, or browser bundles. The committed example contains placeholders only.

## Supabase Auth setup

Phase 1 uses email magic links/OTP and sets `shouldCreateUser: false`, so an email request cannot create an account. Before local use:

1. Create the approved operator users in Supabase Auth through an authorized administrative process.
2. Disable public sign-up in the Supabase Auth project configuration.
3. Add the local callback URL (`http://localhost:3000/auth/callback`, or the matching local origin) to the allowed redirect URLs.
4. Put only the approved user addresses in `CREATOR_ANALYTICS_ALLOWED_EMAILS`.

The route proxy performs only an optimistic session check. The server-only authorization layer validates the user with Supabase Auth and independently checks the email allowlist before every SELECT.

## Least-privilege data access

Migration 033 defines the production data-access foundation:

- `creator_analytics_web_reader` is a restricted server-only login with read-only transaction defaults, bounded statement and idle-transaction timeouts, `SELECT` only on the application projections, and `EXECUTE` only on six private read helpers needed by nested security-invoker or function-backed sources.
- `creator_analytics_web_view_owner` is a no-login role that owns the projections and has only the source access needed to evaluate them.
- `creator_app` is a private, unexposed schema containing exact column projections for the Phase 1 routes. `PUBLIC`, `anon`, `authenticated`, `service_role`, and `creator_dashboard_reader` receive no access to it.
- Browser code continues to use the publishable key only for Supabase Auth. Data queries use the restricted PostgreSQL connection after the server independently validates the session and email allowlist.

Migration 033 intentionally contains no password. An authorized operator must provision the reader password separately, store the resulting pooler URL only in the hosting platform's encrypted server environment, and validate the grants in staging before production. Do not use the Supabase service-role/secret key as a substitute.

Current read surfaces:

- Dashboard: `looker_dashboard_posts`, `looker_daily_growth`, `looker_posting_time_summary`, and `looker_content_performance_summary`.
- Upcoming Posts: `dashboard_posts` and `looker_schedule_change_proposals`.
- Label Queue: `unlabeled_posts_queue`, `pending_label_queue_exports`, and a bounded recent relationship read from `looker_dashboard_posts`.
- Schedule Approvals: `looker_schedule_change_proposals`, `pending_schedule_proposal_exports`, `schedule_change_application_preflight`, `approved_schedule_changes_ready_to_apply`, and synchronized post state from `dashboard_posts`.
- Analytics: `looker_content_performance_summary`, `looker_posting_time_summary`, `looker_joint_posting_recommendations`, `looker_content_aware_fallback_preview`, `looker_scheduling_cadence_settings`, and `looker_weekly_slot_plan`.
- System Status: freshness fields from `dashboard_posts`, proposal errors from `looker_schedule_change_proposals`, blocked Approved proposals from `schedule_change_application_preflight`, `looker_content_aware_proposal_preview_summary`, `looker_scheduling_cadence_settings`, `unlabeled_posts_queue`, and `pending_label_queue_exports`.

Every query names its columns. The data layer has no database mutation or RPC path, omits raw JSON, and converts rows to minimal display DTOs.

The server query compiler also rejects unapproved relations, selected columns, filter columns, sort columns, wildcard selections, overlarge row windows, and malformed ranges. All filter and pagination values are PostgreSQL parameters; callers cannot provide SQL identifiers. Authorization finishes before the lazy database client is acquired.

The scheduling preflight and Make-facing readiness views are queried only by their owning pages. The full preflight and 19-column Make-facing view remain Schedule Approvals-only; System Status reads only blocked preflight rows and the aggregate proposal-preview summary. Heavy recommendation and preview views are never loaded globally. The pages are observation-only: there are no label, export, approval, rejection, proposal refresh, application, ingestion, Buffer, Make, or Google Sheets controls.

System Status is explicitly database-observed. Post-sync health is calculated independently per platform from its newest `last_synced_at`; metrics health uses each platform's newest `latest_metric_captured_at` among sent posts. A newest timestamp exactly on its configured threshold is Fresh, and only an older timestamp is Stale. Summary cards count platforms whose newest observation is Stale or Missing—not historical records outside the threshold. Historical row coverage is informational only.

`automation_runs` is not queried because migrations 001–032 contain no writer and live population is unconfirmed. The page cannot establish live Buffer, Make, or Google Sheets health. Its exported-but-unlinked count is the set difference between current unlinked rows and current pending exports; that database state is not evidence of an external-system failure.

Phase 1 displays dates in `America/Denver`. Any future per-user timezone setting requires a separately reviewed product and data-contract change.

## Commands

```bash
pnpm dev
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build
pnpm test:e2e
pnpm security:scan
```

Unit and component tests use sanitized fixtures and do not require Supabase credentials. The Playwright sign-in smoke test also avoids authentication and production data.

For the browser smoke test, run `pnpm build` and `pnpm start --hostname 127.0.0.1 --port 3100` in one terminal, then run `pnpm test:e2e` in a second terminal. Set `PLAYWRIGHT_BASE_URL` only when testing a different local address.

## Configuration state

Without local credentials, the public sign-in shell still builds. Protected pages render an explicit local-configuration message and do not issue a database request. Do not invent credentials to bypass that state.

## Manual predeployment steps for migration 033

Do not perform these steps against production until the migration and regression evidence has been reviewed and an authorized deployment window is approved.

1. Build a fresh PostgreSQL 17-compatible isolated database through migrations 001–033 and run the migration 029–033 regressions with fatal-on-error.
2. Apply the unchanged committed `Database/033_add_creator_web_read_model.sql` in staging.
3. Generate a unique high-entropy password in the approved secret manager and assign it to `creator_analytics_web_reader` through an authorized administrative SQL session. Never put it in a migration, shell history, ticket, screenshot, or repository file.
4. Obtain the project's exact transaction/session pooler host, port, database, and custom-role username format from the Supabase project connection panel. Build `CREATOR_ANALYTICS_DATABASE_URL` in the hosting secret store with verified TLS; do not guess the pooler format.
5. Keep `creator_app` absent from the Supabase Data API exposed-schema list. Confirm `anon`, `authenticated`, `PUBLIC`, `service_role`, and `creator_dashboard_reader` cannot use the schema or read its views, while the web reader can read all 16 projections and cannot read their public sources directly.
6. Configure the production Site URL and the exact `/auth/callback` redirect URL in Supabase Auth, disable public sign-up, pre-provision approved Auth users, and configure `CREATOR_ANALYTICS_ALLOWED_EMAILS` in the hosting secret store.
7. Run unauthorized, non-allowlisted, direct-browser, authorized-route, sign-out, headers, no-store, and data-minimization smoke tests in staging. Confirm no database URL or role detail appears in browser assets or logs.
8. Promote only after every staging check passes. Roll back the application deployment immediately if authorization or data access fails; database rollback of migration 033 should be a separately reviewed migration that first removes the app deployment and reader sessions, then removes only the 033 schema, policy, and roles.
