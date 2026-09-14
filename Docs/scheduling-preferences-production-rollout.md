# Scheduling Preferences: production rollout, rules OFF

## Approval and current checkpoint

On September 7, 2026, the user approved installing the production setup and deploying the page with new rules kept **Off**. This does not authorize activation, new proposals, approvals, Make runs, or moving existing posts.

Production database `ppgrvebsgefoogulolhs` was verified in the signed-in Supabase project breadcrumb (`creator-analytics`, main Production). Migration 039 is now installed, **disabled at revision 1**. The live website has not yet been deployed with this page; it still needs the private production settings credential and Vercel configuration.

## Installation evidence

- Migration SHA-256: `8dd7babfcabf54248384ae72b0a91bc6fd087d96ed5c6804423cd9e6fa36e8d0` (same tested staging source).
- Executed guarded wrapper SHA-256: `6fe4520c5f11c18bf696e4bb9c32675c81e2924293a9e8f6a09b7fc4144af6ba`.
- Installation timestamp: `2026-09-08T01:52:23.674372Z`.
- Final result: 1,044 posts, 123 proposals, 44 coverage rows, 0 manual baselines, rules Off / revision 1, scheduler account NOLOGIN.
- Independent read-only verification: `2026-09-08T01:54:05.444327Z`.
- Posts hash unchanged: `58a97de5e382c28757e20774094178e5`.
- Proposals hash unchanged excluding two added nullable fields: `7b64cd3a9c75f91760b9224e05d95606`.
- All 16 scheduled posts retained their applied/synchronized schedule and history; no re-anchoring occurred.
- Existing cadence, roles, memberships, generator OID/owner/ACL/config and old generator body were compared inside the transaction and preserved. The only generator additions are the reviewed lock and opt-in dispatch.
- Make feed definition and 19-column contract unchanged: `9cf0ede290b7d40fcc9073bc3abd3699`.
- Both settings rows retain 14/week, maximum 3/day, America/Denver, 24-hour protection; spacing stays 6 hours for TikTok and 4 for YouTube Shorts.
- New settings audit entries: 0. All three permanent tables have RLS. Both reader view grants pass, with no settings-save privilege for anon, authenticated, service_role, dashboard reader, reader, labeler or approver.

The initial confirmation was rejected because the temporary before/after table lacked explicit RLS. Nothing ran. The query was cancelled and strengthened to enable RLS on that temporary table too; the UI then no longer reported the RLS issue, and the safer installation passed all pre-commit assertions. No alternate execution surface or security-disable workaround was used.

The parent workspace retains `production-preferences-before-039.json`, `production-preferences-after-039.json` and `production-preferences-039-installed.sql`. The original scheduler and preflight definitions are retained for recovery; do not automatically roll back or reinstall.

## Page changes and local validation

The existing dashboard styling and infrastructure are preserved. Preferences now require exact approved origin/project pairing for staging versus production, a dedicated matching restricted reader/settings credential pair, verified TLS, and an explicit production-page approval flag. Production copy is distinct from staging copy.

A separate server-only activation gate is closed by default. Production ON submissions are rejected before connecting, even if client form fields are forged. The production On option is disabled while that gate is closed. Existing authentication, revision checks, audit attribution and confirmed-save form behavior remain intact.

Validation passed: 195 tests in 38 files, Next production build/TypeScript, ESLint, and security scan of 137 source/configuration files. No dependencies or lockfiles changed.

## Private credential handoff (next required user action)

Parent-workspace `Setup-Production-Scheduling-Settings.ps1` is prepared. `-CheckFilesOnly` and PowerShell parsing passed. Its SQL preflight passed read-only against production. It targets only `ppgrvebsgefoogulolhs` through `aws-1-us-west-2.pooler.supabase.com:5432`, with the pinned verified Supabase root CA.

1. User runs the helper in a separate PowerShell process and privately enters the existing **production postgres database administrator password**.
2. User creates a new unique `creator_analytics_web_scheduler` password twice, then re-enters it for restricted login verification.
3. Only the verified connection URL is copied; never inspect the clipboard or ask for passwords/URLs in chat. If provisioning succeeds but verification fails, use `-VerifyOnly`, not another password reset.
4. User saves that value as Secret `CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL` in Vercel project **creator-analytics**, Production environment. The staging secret must not be reused.

The helper refuses an existing password, unsafe role privileges/membership, changed inventory, activated preferences, or changed Make contract. It permits only Supabase's exact ADMIN-only provider management membership. It does not change posts, proposals or preferences.

## Remaining deployment steps

After the user confirms the production secret is saved:

- Set Config `CREATOR_ANALYTICS_PREFERENCES_ENABLED=true` and `CREATOR_ANALYTICS_PREFERENCES_PRODUCTION_APPROVED=true` in the production project.
- Keep Config `CREATOR_ANALYTICS_PREFERENCES_ACTIVATION_APPROVED=false` (missing also denies activation).
- Publish the tested source to `creator-analytics`, preserving its existing production origin/Auth/reader/labeler/approver configuration. The source branch's automatic deployments remain disabled, so use an explicit reviewed deployment.
- Verify the authenticated production page shows Production / Rules off, targets 14 and ceilings 3, and coverage. Verify the activation lock without submitting an ON change.
- Recheck database Off state and preservation evidence. Do not run Make, generate proposals, activate rules or modify the current 16-post batch.

Only after this OFF rollout is complete should activation for future history-free uploads be separately considered. Existing posts with proposal history must not acquire a synthetic manual baseline.
