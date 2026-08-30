# Creator Analytics web app

Phase 1 is a private, read-only Next.js interface over the existing Creator Analytics Supabase reporting surfaces. It does not replace or trigger Buffer, Make, Google Sheets, Looker Studio, ingestion, labeling, proposal generation, approval, or schedule application workflows.

## Local configuration

Copy `.env.example` to `.env.local` and replace every placeholder locally. Never commit `.env.local` or paste its contents into logs, screenshots, tests, or documentation.

Required variables:

- `NEXT_PUBLIC_SUPABASE_URL`: browser-safe project URL used by Supabase Auth.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: browser-safe publishable/anon key used only for Auth session handling.
- `CREATOR_ANALYTICS_ALLOWED_EMAILS`: comma-separated approved email addresses. Authorization normalizes case and checks this server-side before every database SELECT.
- `CREATOR_ANALYTICS_APP_ORIGIN`: local application origin used for magic-link callbacks, such as `http://localhost:3000`.
- `SUPABASE_SERVER_SECRET_KEY`: temporary server-only credential used by the read-only data layer because migrations 001–032 do not define an authenticated web-app access model.
- `CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS`: database post-sync freshness threshold; defaults to `6` hours.
- `CREATOR_ANALYTICS_METRICS_STALE_HOURS`: database metrics freshness threshold; defaults to `48` hours.

The server secret must never use a `NEXT_PUBLIC_` prefix. It is imported only by `server-only` modules and is not returned in DTOs, HTML, errors, logs, screenshots, fixtures, or browser bundles.

## Supabase Auth setup

Phase 1 uses email magic links/OTP and sets `shouldCreateUser: false`, so an email request cannot create an account. Before local use:

1. Create the approved operator users in Supabase Auth through an authorized administrative process.
2. Disable public sign-up in the Supabase Auth project configuration.
3. Add the local callback URL (`http://localhost:3000/auth/callback`, or the matching local origin) to the allowed redirect URLs.
4. Put only the approved user addresses in `CREATOR_ANALYTICS_ALLOWED_EMAILS`.

The route proxy performs only an optimistic session check. The server-only authorization layer validates the user with Supabase Auth and independently checks the email allowlist before every SELECT.

## Least-privilege deployment blocker

The broad server secret is supported only as a temporary local-development bridge. It bypasses RLS and has capabilities far beyond this interface. **Do not deploy Phase 1 with that credential.** Before any deployment, add and validate a separately approved least-privilege database access model that can read only the required reporting columns/views, then remove the broad server-secret path.

Current read surfaces:

- Dashboard: `looker_dashboard_posts`, `looker_daily_growth`, `looker_posting_time_summary`, and `looker_content_performance_summary`.
- Upcoming Posts: `dashboard_posts` and `looker_schedule_change_proposals`.
- Label Queue: `unlabeled_posts_queue`, `pending_label_queue_exports`, and a bounded recent relationship read from `looker_dashboard_posts`.
- Schedule Approvals: `looker_schedule_change_proposals`, `pending_schedule_proposal_exports`, `schedule_change_application_preflight`, `approved_schedule_changes_ready_to_apply`, and synchronized post state from `dashboard_posts`.
- Analytics: `looker_content_performance_summary`, `looker_posting_time_summary`, `looker_joint_posting_recommendations`, `looker_content_aware_fallback_preview`, `looker_scheduling_cadence_settings`, and `looker_weekly_slot_plan`.
- System Status: freshness fields from `dashboard_posts`, proposal errors from `looker_schedule_change_proposals`, blocked Approved proposals from `schedule_change_application_preflight`, `looker_content_aware_proposal_preview_summary`, `looker_scheduling_cadence_settings`, `unlabeled_posts_queue`, and `pending_label_queue_exports`.

Every query names its columns. The data layer has no database mutation or RPC path, omits raw JSON, and converts rows to minimal display DTOs.

The scheduling preflight and Make-facing readiness views are queried only by their owning pages. The full preflight and 19-column Make-facing view remain Schedule Approvals-only; System Status reads only blocked preflight rows and the aggregate proposal-preview summary. Heavy recommendation and preview views are never loaded globally. The pages are observation-only: there are no label, export, approval, rejection, proposal refresh, application, ingestion, Buffer, Make, or Google Sheets controls.

System Status is explicitly database-observed. `automation_runs` is not queried because migrations 001–032 contain no writer and live population is unconfirmed. The page cannot establish live Buffer, Make, or Google Sheets health. Its exported-but-unlinked count is the set difference between current unlinked rows and current pending exports; that database state is not evidence of an external-system failure.

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
```

Unit and component tests use sanitized fixtures and do not require Supabase credentials. The Playwright sign-in smoke test also avoids authentication and production data.

For the browser smoke test, run `pnpm build` and `pnpm start --hostname 127.0.0.1 --port 3100` in one terminal, then run `pnpm test:e2e` in a second terminal. Set `PLAYWRIGHT_BASE_URL` only when testing a different local address.

## Configuration state

Without local credentials, the public sign-in shell still builds. Protected pages render an explicit local-configuration message and do not issue a database request. Do not invent credentials to bypass that state.
