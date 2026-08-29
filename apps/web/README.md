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

Every query names its columns. The data layer has no database mutation or RPC path, omits raw JSON, and converts rows to minimal display DTOs.

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
