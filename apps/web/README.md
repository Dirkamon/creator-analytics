# Creator Analytics web app

Creator Analytics is a private Next.js interface over the existing Supabase reporting surfaces. Its default deployment remains read-only. Migrations 035–036 add independently gated labeling with atomic Make ownership. Migration 037 adds an independently gated, audited Schedule Approvals decision path with the same atomic ownership model. Production mutations require separate exact-host opt-ins and remain disabled by default. The app never triggers Buffer, Make, Google Sheets export, Looker Studio, ingestion, proposal generation, or schedule application workflows.

## Local configuration

Copy `.env.example` to `.env.local` and replace every placeholder locally. Never commit `.env.local` or paste its contents into logs, screenshots, tests, or documentation.

Required variables:

- `NEXT_PUBLIC_SUPABASE_URL`: browser-safe project URL used by Supabase Auth.
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: browser-safe publishable/anon key used only for Auth session handling.
- `CREATOR_ANALYTICS_ALLOWED_EMAILS`: comma-separated approved email addresses. Authorization normalizes case and checks this server-side before every database SELECT.
- `CREATOR_ANALYTICS_APP_ORIGIN`: local application origin used for magic-link callbacks, such as `http://localhost:3000`.
- `CREATOR_ANALYTICS_DATABASE_URL`: server-only PostgreSQL connection URL for the migration-033 `creator_analytics_web_reader` role. Use the Supabase pooler and verified TLS in production.
- `CREATOR_ANALYTICS_LABELING_ENABLED`: defaults to `false`. This is the immediate labeling kill switch.
- `CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED`: defaults to `false`. It must also be `true` to allow labeling on the exact production host `creator-analytics-theta.vercel.app`; it does not permit any other production hostname.
- `CREATOR_ANALYTICS_LABEL_DATABASE_URL`: required only when controlled labeling is enabled. This server-only URL must use the migration-035 `creator_analytics_web_labeler` role and the same verified-TLS pooler rules as the reader URL.
- `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED`: defaults to `false`. This is the immediate Schedule Approvals decision kill switch.
- `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_PRODUCTION_APPROVED`: defaults to `false`. It must also be `true` to allow decisions on the exact production host; it does not permit any other production hostname.
- `CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL`: required only when controlled decisions are enabled. This server-only URL must use the migration-037 `creator_analytics_web_approver` role and the same verified-TLS pooler rules as the reader URL.
- `CREATOR_ANALYTICS_POST_SYNC_STALE_HOURS`: database post-sync freshness threshold; defaults to `15` hours to allow for the approximately 12-hour post-sync cadence while remaining configurable.
- `CREATOR_ANALYTICS_METRICS_STALE_HOURS`: database metrics freshness threshold; defaults to `48` hours.

Database URLs must never use a `NEXT_PUBLIC_` prefix. They are imported only by a `server-only` module and are not returned in DTOs, HTML, errors, logs, screenshots, fixtures, or browser bundles. The committed example contains placeholders only.

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

Migration 035 defines a separate controlled-labeling boundary:

- `creator_analytics_web_labeler` is a server-only login with no direct table access and access to only the controlled wrapper among operational mutation functions.
- `process_content_label_payload_for_web` accepts only unlabeled posts whose Sheet export timestamp is still empty, locks the post and normalized Clip Group, preserves every label when linking an existing group, and writes an operator audit record in the same transaction.
- A normalized unique index prevents case-only Clip Group duplicates while preserving the display case of existing groups.
- Already-exported rows are rejected and remain owned by the Make/Google Sheets fallback. The app never marks a queue row exported.
- Migration 036 forces Make to claim each export row atomically before its Sheet write. A claimed row is displayed as `Export in progress` and cannot be labeled by the app; a row labeled by the app cannot be claimed.
- Make must finalize with the exact opaque claim token. The old direct queue read and one-argument export marker are removed from `service_role`, so a stale scenario fails closed.
- Claims are not automatically reclaimed. If a Sheet write succeeds but finalization fails, automatic reclaim could duplicate the row; inspect Make and Sheets before any manual recovery.
- The feature flag is fail-closed and is rejected for a non-staging, non-loopback origin unless the separate production approval flag is enabled for the exact production hostname.

Migration 037 defines a separate controlled-scheduling boundary:

- `creator_analytics_web_approver` is a server-only login with no direct table access and access to only `process_schedule_proposal_decision_for_web`.
- The wrapper accepts only a current Pending proposal, an exact expected version timestamp, an Approved or Rejected decision, and the authorized operator email. It rejects stale pages, duplicate decisions, exported or Make-claimed proposals, and approvals that fail the current database preflight.
- Each successful decision and its `web_schedule_decision_events` audit row are committed in one transaction. A rejected attempt changes neither the proposal nor the audit table.
- Make must claim Schedule Approvals exports through `claim_pending_schedule_proposal_exports`, preserve the opaque claim token through the Sheet write, and finalize with `mark_schedule_proposal_exported(proposal_id, claim_token)`.
- The Sheet decision scenario must call `set_exported_schedule_proposal_decision`; it can decide only a proposal finalized to Sheets. The service role cannot execute the legacy unrestricted decision function.
- An app-decided proposal cannot be claimed by Make, and a claimed or exported proposal cannot be decided in the app. This keeps each proposal under exactly one decision interface.
- Approval records a decision only. The existing Make application scenario remains the sole Buffer-changing component, and the UI never presents Approved as Applied.

Migration 033 intentionally contains no password. An authorized operator must provision the reader password separately, store the resulting pooler URL only in the hosting platform's encrypted server environment, and validate the grants in staging before production. Do not use the Supabase service-role/secret key as a substitute.

Current read surfaces:

- Dashboard: `looker_dashboard_posts`, `looker_daily_growth`, `looker_posting_time_summary`, and `looker_content_performance_summary`.
- Top Posts: a paginated, sortable browser view over the bounded `looker_dashboard_posts` read, with platform, game, and America/Denver date filters.
- Upcoming Posts: `dashboard_posts` and `looker_schedule_change_proposals`.
- Label Queue: `unlabeled_posts_queue`, explicit pending/claimed/exported state from `creator_app.pending_label_queue_exports`, and a bounded recent relationship read from `looker_dashboard_posts`; when the independently gated labeling flags are enabled, unclaimed rows can use the controlled migration-035 labeling wrapper.
- Schedule Approvals: `looker_schedule_change_proposals`, token-free ownership state from `creator_app.pending_schedule_proposal_exports`, `schedule_change_application_preflight`, `approved_schedule_changes_ready_to_apply`, and synchronized post state from `dashboard_posts`; when the independently gated decision flags are enabled, app-owned Pending proposals can use the controlled migration-037 wrapper.
- Analytics: `looker_content_performance_summary`, `looker_posting_time_summary`, `looker_joint_posting_recommendations`, `looker_content_aware_fallback_preview`, `looker_scheduling_cadence_settings`, and `looker_weekly_slot_plan`.
- System Status: freshness fields from `dashboard_posts`, proposal errors from `looker_schedule_change_proposals`, blocked Approved proposals from `schedule_change_application_preflight`, `looker_content_aware_proposal_preview_summary`, `looker_scheduling_cadence_settings`, `unlabeled_posts_queue`, and `pending_label_queue_exports`.

Every read query names its columns. The read compiler has no mutation path, omits raw JSON, and converts rows to minimal display DTOs. Label and decision writes use independent clients, independent credentials, one fixed SQL call per feature, and server-side validation after authorization.

The server query compiler also rejects unapproved relations, selected columns, filter columns, sort columns, wildcard selections, overlarge row windows, and malformed ranges. All filter and pagination values are PostgreSQL parameters; callers cannot provide SQL identifiers. Authorization finishes before the lazy database client is acquired.

The scheduling preflight and Make-facing readiness views are queried only by their owning pages. The full preflight and 19-column Make-facing view remain Schedule Approvals-only; System Status reads only blocked preflight rows and the aggregate proposal-preview summary. Heavy recommendation and preview views are never loaded globally. All pages remain observation-only except the independently gated Label Queue and Schedule Approvals forms. There are no export, proposal refresh, application, ingestion, Buffer, Make, or Google Sheets controls.

System Status is explicitly database-observed. Post-sync health is calculated independently per platform from its newest `last_synced_at`; metrics health uses each platform's newest `latest_metric_captured_at` among sent posts. A newest timestamp exactly on its configured threshold is Fresh, and only an older timestamp is Stale. Summary cards count platforms whose newest observation is Stale or Missing—not historical records outside the threshold. Historical row coverage is informational only.

`automation_runs` is not queried because migrations 001–032 contain no writer and live population is unconfirmed. The page cannot establish live Buffer, Make, or Google Sheets health. Its exported-but-unlinked count is the set difference between current unlinked rows and current pending exports; that database state is not evidence of an external-system failure.

Phase 1 displays and filters dates in `America/Denver`. Proposal timestamps use each row's stored timezone when one is present. Any future per-user timezone setting requires a separately reviewed product and data-contract change.

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

## Manual staging steps for migration 035

Keep labeling disabled while deploying the application code. Complete and verify Phase 3 coexistence in staging before using the separate production rollout below.

1. Run migrations 001–035 and `Tests/Database/035_add_controlled_web_labeling_regression.sql` in a fresh PostgreSQL 17-compatible sandbox with fatal-on-error.
2. Apply `Database/035_add_controlled_web_labeling.sql` in staging. If the normalized Clip Group index reports a case-only duplicate, stop and review those groups; do not delete or merge them automatically.
3. Create a unique high-entropy password for `creator_analytics_web_labeler` outside the repository and assign it through an authorized administrative session.
4. Store the labeler pooler URL as the encrypted `CREATOR_ANALYTICS_LABEL_DATABASE_URL` hosting secret. Confirm the username is exactly the labeler role plus the project reference, and use `sslmode=verify-full` with the system root certificate.
5. Leave `CREATOR_ANALYTICS_LABELING_ENABLED=false` until the reader deployment, migration, labeler login, and authorized sign-in are independently verified.
6. Coordinate or pause the staging Label Queue exporter during acceptance testing; the database cannot see a row that Make fetched but has not yet marked. Enable the flag only on the staging origin. Test a new Clip Group, a confirmed existing-group link, a rejected missing confirmation, and a row that Make has already marked exported.
7. Verify each successful action has one `web_labeling_events` audit row, rejected attempts change no post or content item, and the existing Google Sheets/Make workflow still processes exported rows.
8. To disable immediately, set `CREATOR_ANALYTICS_LABELING_ENABLED=false` and redeploy. Keep the migration and audit records in place; database-object removal requires a separately reviewed rollback migration.

## Manual staging steps for migration 036

Keep the staging Label Queue exporter paused until both database and Make changes are ready.

1. Run migrations 001–036 and `Tests/Database/036_add_atomic_label_queue_export_claims_regression.sql` in a fresh PostgreSQL 17-compatible sandbox with fatal-on-error. Rerun migration 036 once to prove it is repeatable.
2. Apply `Database/036_add_atomic_label_queue_export_claims.sql` in staging. This immediately disables the old service-role queue read and one-argument export marker, so do not reactivate the old Make scenario.
3. Change the first Make request to `claim_pending_label_queue_exports` and iterate its returned rows. Preserve the returned `claim_token` through the Google Sheets step.
4. Change the final Make request to `mark_label_queue_exported(post_id, claim_token)`. Treat `false` as a stopped/error run rather than success.
5. With the scenario still paused, run an empty-queue test, then one controlled staging row. Confirm the app shows `Export in progress` after claim and `Exported · still unlinked` only after the matching finalize call.
6. Verify the same claimed row is rejected by the web labeler, an app-labeled row is not returned to Make, a wrong token cannot finalize, and a repeated finalize returns false without creating another Sheet row.
7. Reactivate only the staging scenario after comparing its new Sheet row with the established header/mapping contract. Production promotion remains a separate reviewed change.

## Production labeling rollout

Production labeling remains off unless both labeling flags and the restricted labeler connection are present. Promotion is limited to the exact production hostname compiled into the server configuration.

1. Confirm migrations 035 and 036 exist in production, the labeler role retains its least-privilege attributes and sole labeling wrapper, and the Make service role can use only the atomic claim/finalize contract.
2. Confirm the production `Supabase to Google Sheets - Label Queue` scenario uses `claim_pending_label_queue_exports` and finalizes with `mark_label_queue_exported(post_id, claim_token)` before leaving it active.
3. Generate a new, unique password for the production `creator_analytics_web_labeler` role outside the repository. Store only its verified-TLS pooler URL in the encrypted production `CREATOR_ANALYTICS_LABEL_DATABASE_URL` variable.
4. Deploy this code with `CREATOR_ANALYTICS_LABELING_ENABLED=false` and `CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED=false`, then verify the existing read-only production smoke tests.
5. Set `CREATOR_ANALYTICS_LABELING_PRODUCTION_APPROVED=true` and `CREATOR_ANALYTICS_LABELING_ENABLED=true`, then redeploy. Verify an authenticated Label Queue displays controls only for `Pending export` rows.
6. For the first available unclaimed row, perform one controlled new-group label. Confirm the post is linked, one `web_labeling_events` row records the operator, and Make does not later export that post. Then verify one explicitly confirmed existing-group link.
7. To disable immediately, set `CREATOR_ANALYTICS_LABELING_ENABLED=false` and redeploy. Keep the production approval flag, database objects, credential, and audit records in place unless a separately reviewed rollback or credential-rotation procedure requires changing them.

## Manual staging steps for migration 037

Keep `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED=false`. Pause both `Supabase to Google Sheets - Schedule Approvals` and `Google Sheets to Supabase - Schedule Decisions` before applying the migration; migration 037 deliberately makes their legacy database calls fail closed.

1. Run migrations 001–037 in a fresh PostgreSQL 17-compatible sandbox with fatal-on-error, rerun migration 037 to prove repeatability, and run `Tests/Database/037_add_controlled_web_schedule_decisions_regression.sql`.
2. Apply `Database/037_add_controlled_web_schedule_decisions.sql` in staging while both scheduling Sheet scenarios remain paused.
3. Update the export scenario to call `claim_pending_schedule_proposal_exports(limit)`, iterate only those returned rows, preserve each `claim_token` through its Google Sheets write, and call `mark_schedule_proposal_exported(proposal_id, claim_token)` afterward. Treat `false` as a stopped/error run.
4. Update the Sheet decision scenario to call `set_exported_schedule_proposal_decision(proposal_id, decision)`. Do not call the legacy `set_schedule_proposal_decision` function.
5. With both scenarios still paused, test an empty claim, one exact-token Sheet export/finalize, a wrong token, a duplicate finalize, and one Sheet decision. Verify the app cannot decide the claimed/finalized proposal and Make cannot claim an app-decided proposal.
6. Create a unique high-entropy password for `creator_analytics_web_approver` outside the repository. Store only its verified-TLS pooler URL in the encrypted staging `CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL` variable.
7. Enable `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED=true` only on staging. Test one Rejected proposal and one preflight-safe Approved proposal, plus a duplicate click, stale page, missing confirmation, and preflight failure. Verify exactly one audit row per successful decision and no audit row for any rejected attempt.
8. Confirm Approved still requires the existing Make application scenario before Buffer changes. Reactivate the two staging Sheet scenarios only after their new claim/finalize and exported-decision contracts both pass.
9. To disable the web path immediately, set `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED=false` and redeploy. The updated Make/Sheets fallback remains available.

## Production Schedule Approvals rollout

Production Schedule Approvals decisions remain off unless both decision flags and the restricted approver connection are present. Promotion is limited to the exact production hostname compiled into the server configuration.

1. Complete and record every migration-037 staging check above. Do not reuse staging credentials, claim tokens, or test proposals.
2. Pause both production scheduling Sheet scenarios, apply migration 037, update the export scenario to the claim/token/finalize contract, and update the Sheet decision scenario to `set_exported_schedule_proposal_decision`. Validate both before resuming either scenario.
3. Generate a new production approver password outside the repository and store only its verified-TLS pooler URL in encrypted `CREATOR_ANALYTICS_SCHEDULE_DATABASE_URL`.
4. Deploy with `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED=false` and `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_PRODUCTION_APPROVED=false`, then repeat the existing read-only smoke tests.
5. Set both decision flags to `true` and redeploy only during an approved rollout window. Verify controls appear only on app-owned, unclaimed, unexported Pending proposals.
6. Perform one controlled Rejected decision first. Then approve one preflight-safe proposal and verify the audit record, Make application handoff, Buffer result, and later post-sync evidence independently.
7. To disable immediately, set `CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED=false` and redeploy. Keep the updated Make contract active; database-object removal or credential rotation requires a separately reviewed procedure.
