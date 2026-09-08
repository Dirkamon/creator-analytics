# Scheduling preferences — implementation handoff, September 7, 2026

## Actual status

Implemented locally and **installed on hosted staging with the new rules OFF** on September 7, 2026. **Not yet deployed to the staging app and not active in production**. The user completed the private scheduler credential flow and confirmed the copied connection was saved. Vercel metadata independently confirms `CREATOR_ANALYTICS_PREFERENCES_DATABASE_URL` is a Secret in the Production environment of **creator-analytics-staging**. Its value was not read. The staging UI flag `CREATOR_ANALYTICS_PREFERENCES_ENABLED=true` was also saved and verified by name/type/environment. These environment changes require a new staging deployment; they do not activate the database generator.
The existing development-only illustration at port 3107 remains separate from the real authenticated form.

The user explicitly approved the isolated rollback-only hosted staging rehearsal, including temporary test data and role grants, after the earlier approval-review pause. That rehearsal **passed on September 7, 2026**. All 25 independent before/after audit fields match. At that historical checkpoint the settings were not installed or deployed; the test transaction rolled back. This approval did not authorize permanent installation, credentials, activation, or production changes.

Latest continuation: after the permanent-installation approval pause, the user explicitly answered **yes** to adding the new staging database tables and restricted settings account with the rules disabled and production untouched. Installation has now committed successfully. Do not ask for that approval again or rerun the uninstalled-state rehearsal. See `scheduling-preferences-staging-installed.md` for the installation and access evidence.

## Implemented

- Migration 039 installs a versioned singleton, audited narrow settings-save function, immutable manual Buffer-time baselines, and an opt-in generator. It starts disabled and never contacts Buffer.
- Target 14/platform/week, initial ceiling 3/platform/day, minimum daily coverage 1 when feasible, any publishing hour, ±12 **elapsed** hours from the original manual schedule. No accumulated drift. Existing manual approvals, timezone, protected lead time, spacing, reservation, history, and capacity checks remain.
- The original Make refresh signatures and 19-column approved feed remain. A shared guard checks preference/cadence revisions, original baseline, movement bounds, timezone, and guaranteed source-day coverage at proposal insertion/approval and feed reads.
- Coverage-first candidate selection uses the existing analytics and four-hour-window midpoints, rather than the illustrative TypeScript counts. Incoming unapproved posts cannot justify removing the last guaranteed post from another day.
- Read views use the existing NOLOGIN reporting-owner role and narrow security-definer read functions. No source-table access is granted to the web reader. The new `creator_analytics_web_scheduler` role starts **NOLOGIN**; only it may execute the settings-save function. No password was created or collected.
- New authenticated `/scheduling-preferences` form and read-only coverage table. Server-side allowlist authorization, input validation, confirmation, expected revision, safe errors, and server-derived audit actor. The page/action are hard-gated to `https://creator-analytics-staging.vercel.app` and staging project `iepwctcayajdpvsmfmgl`, with distinct verified-TLS reader/settings credentials. No production override exists in this slice.
- Reused existing theme tokens/layout under the Sites skill; no redesign or hosting-provider change. Extended the security scan for the new server-only credential name.

## Verified locally

- PostgreSQL 17.6: migration installs/reruns; real generator fixtures; exact ±12-hour limits and just outside; repeat-run idempotency; 14 generated proposals with sparse inventory; adjacent-day coverage priority; lost source-day coverage blocked at the shared gate; stale settings/current-time checks; actual restricted reader, Make-service, and settings-writer calls; audited save and stale-write rejection; no/short/stale inventory; date bounds; basic DST elapsed-hour fixtures; 128 TikTok approval subsets checked for spacing, daily/weekly limits and preserved coverage. All fixtures rolled back.
- Migration 038 versioned export/decision regression also passes after 039, rollback-only.
- Historical 034–036 chain stops at migration 032's exact wrapper-definition hash expectation. Historical 037 expects the old service-role export grant that migration 038 intentionally removes. These version-specific suites have **not** been reported as passing against the combined current schema; no expectations were weakened.
- 179 web tests across 38 files pass. Production build/TypeScript, full ESLint, security scan (137 source/configuration files), and `git diff --check` pass.
- Six actual multi-session tests now pass (`Tests/Database/039_concurrency.mjs`): stale concurrent save rejection; serialized generation without duplicates; save blocked by newly generated unresolved proposals; generation reads the committed settings revision; activation and deactivation races select the correct scheduler path. Each used its own uniquely named local database clone; all clones were removed, leaving the original empty disposable database unchanged.
- The activation test initially failed because dispatch read the enabled flag before obtaining the shared lock. Migration 039 now takes the shared transaction-reentrant lock before selecting the old/new path. The full 039 and 038 database regressions, 179 web tests, build/TypeScript, ESLint and security scan were rerun successfully after the fix. The corrected hosted rehearsal passed with full rollback and matching audit fingerprints.
- No browser visual QA of the new authenticated form and no authenticated hosted save round trip yet.

## Historical rollback-only staging attempts and audit (before installation)

Verified breadcrumb **Creator Analytics Staging**, project `iepwctcayajdpvsmfmgl` before every hosted work segment. Never used the production project for these changes.

Rollback-only attempts exposed two hosted differences: deployment account lacks CREATE on the locked-down `creator_app` schema, and cannot automatically SET ROLE to the restricted web reader. Migration now follows the existing reporting-owner pattern; the test includes temporary SET-only role grants inside the rollback transaction. The UI editor also required explicit Select All / Backspace before fill; otherwise Monaco appended to the old query.

The next retry was initially rejected by automatic approval review at the **Run without RLS** confirmation. Despite that UI label, the SQL does not disable existing RLS; new persistent tables explicitly enable RLS, while transaction-local fixture tables are temporary. The warning was cancelled, staging was audited unchanged, and explicit approval was requested for temporary data updates and impersonation grants. The user then approved that exact rollback-only test. The same reviewed artifact was run through the staging editor without rewriting its SQL, and completed successfully at its final `after_rollback` result. No alternate interface was used to bypass the earlier rejection.

Final hosted audit:

- `preferences_installed`: false
- `new_role_exists`: false
- Posts: 25; non-demo posts: 0
- Proposals: 4 — Error 1, Approved 1, Rejected 2
- Make feed definition MD5 unchanged: `9cf0ede290b7d40fcc9073bc3abd3699`
- Independent before/after comparison: **25 fields, zero differences**, including full-row fingerprints for posts, proposals, cadence, organizations, channels, content items and metric snapshots; roles and memberships; database/schema ACLs; relation ownership/ACLs/RLS flags; function definitions/ACLs; view definitions; policies; columns; constraints; and triggers. The Make feed still has 19 columns. See `scheduling-preferences-hosted-rehearsal-evidence.md` for the recorded fingerprints.

At that historical rollback-only checkpoint, no hosted migration remained installed. The later explicitly approved installation is recorded above and in the installation evidence. No Make scenarios, live approvals, production configuration, Google Sheets, or Buffer posts were changed. There was no source commit, push, or app deployment.

## Next steps (separate from the completed rehearsal)

1. Read this note and re-audit staging before new work. The initial rollback-only artifact refuses an already-installed preferences table and must not be rerun as-is now. Verify the project breadcrumb separately; a database named `postgres` is not environment identity.
2. The approved hosted rollback-only rehearsal, simultaneous-session checks, and permanent staging installation are complete. Installed state: disabled revision 1; scheduler NOLOGIN; two settings view rows; 88 coverage rows; one history-free manual baseline captured; zero settings audit entries. Existing 25 posts and four proposals remain unchanged.
3. Existing approved demo proposals must be deliberately resolved before saving settings; do not silently change them as part of credential setup or installation. The installed-proposal row hash must omit the two new nullable preference columns when comparing it with the pre-install hash. Existing role memberships remain identical; the new account has only the provider-generated ADMIN-only management grant from supabase_admin to postgres (SET=false, INHERIT=false). The credential scripts accept only that exact management grant and reject broader memberships.
4. The user has now run the prepared `Setup-Staging-Scheduling-Settings.ps1` privately and reported the verified connection copied, then saved. Do not reset the password or inspect the clipboard. If private verification is needed later, use `-VerifyOnly`. The script refuses unexpected inventory/settings, existing passwords and excessive privileges, validates the pinned Supabase CA, and targets only `iepwctcayajdpvsmfmgl` via the west-2 staging pooler. No credential value entered chat or source.
5. Both staging-only environment variables are saved. Deploy only staging, validate the restricted connection through the authenticated application, test the authorized save/read flow, and activate only in a controlled staging test. The application flag does not itself enable the database generator. A dedicated `staging/scheduling-preferences` branch is planned; `apps/web/vercel.json` disables automatic Git deployments for exactly that branch, so the shared repository cannot automatically build it in the real production Vercel project. Release manually from the staging project only. Existing branch tracking and production deployment must remain unchanged.
6. Production rollout remains a separate approval and verification step.

## Deliberate limitations

- Preserves the existing two-day planning runway and +23-day upper bound; a 12-hour movement limit does not let it fill arbitrary days from distant inventory.
- Daily coverage is best-effort within inventory, fresh evidence and safety limits. The greedy allocator is not a global optimizer and does not promise a feasible swap will always be found.
- Existing conservative reservations count original and proposed times until applied/synchronized. A full week can therefore limit further proposals. This protects arbitrary approval subsets but is not a newly optimized capacity model.
- Uses existing scheduled-post capacity semantics; does not redefine how previously published posts contribute to cadence. Basic DST arithmetic tests are not exhaustive ambiguous/nonexistent-local-time generator tests.
- Historical/applied posts are not re-opened. A deliberate new manual schedule after proposal history needs an explicit future reset workflow; it is not silently treated as a new baseline.
- The coverage table shows observed and hypothetical planned counts, not live Buffer state, guaranteed coverage, or a simulation of unsaved form edits. Empty days have a general eligibility explanation, not a proved per-day root-cause classification.

## Local runtime

The isolated PostgreSQL cluster used for tests is in `C:/Users/jayjg/AppData/Local/Temp/CreatorAnalytics-Preferences039-a5c5d5c7c65247979c646862bcfbd7ef/data`, bound only to 127.0.0.1:55479. It was successfully **stopped** after final checks; its files were retained for reproducibility. The user's existing design preview on port 3107 was not stopped.

Reviewed artifact SHA-256 hashes:

- Migration 039 (after dispatch concurrency fix): `8DD7BABFCABF54248384AE72B0A91BC6FD087D96ED5C6804423CD9E6FA36E8D0`
- Regression 039: `BE5509C6797B8157BC04CDB365EC629DDC1900E222FB0D315935C07D9E7A6BDA`
- Generated hosted rehearsal (after dispatch concurrency fix): `0EB08F9B4FD360241CA6598C6AA8E1A4758874834CF5D7DA10C1E223BBC51CCB`
