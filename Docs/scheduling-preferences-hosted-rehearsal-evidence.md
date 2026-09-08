# Hosted scheduling-preferences rehearsal — September 7, 2026

## Scope and outcome

User explicitly approved the rollback-only hosted staging test after a prior approval-review pause. Target identity was verified in the visible Supabase breadcrumb and URL: **Creator Analytics Staging**, `iepwctcayajdpvsmfmgl`. No production database, Buffer, Make scenario, Google Sheet, deployment or credential was changed.

Executed `Tests/Database/039_staging_rehearsal.generated.sql` exactly as reviewed, SHA-256 `a92e585dea7d1941d67898b9082379d03fed2c4707794ed84165ee4a236ac7e9`. The script contains migration 039 and its regression in one transaction ending with ROLLBACK, then a final read-only verification query. Existing RLS was not disabled. Temporary test impersonation grants and all new objects rolled back.

The SQL editor completed without an error and returned its final `after_rollback` result:

```json
{"posts":25,"proposals":4,"make_contract":"9cf0ede290b7d40fcc9073bc3abd3699","new_role_exists":false,"preferences_installed":false}
```

This is the final result after the regression assertions and rollback, not a separately fabricated success marker. The editor displayed only the last result set; individual notices were not captured.

## Independent cleanup audit

The same read-only audit was executed immediately before and after the rehearsal. Its parsed JSON comparison found **25 fields and zero differences**. Whole-row data hashes used deterministic ordering. Catalog fingerprints include definitions and security attributes, not only object counts. These are equality checks, not authentication credentials.

| Audit field | Before = after |
| --- | --- |
| posts | 25 |
| proposals | 4 |
| non_demo_posts | 0 |
| preferences_installed | false |
| new_role_exists | false |
| make_columns | 19 |
| posts_hash | `74a242b590f616280bad190be380deca` |
| proposals_hash | `8a36f7f9773d38bff6b2cf7acf5fd33b` |
| cadence_hash | `4bc1865c45fa66ccbd35ad187db4ac7f` |
| organizations_hash | `895ef3d55e40ee808e1b0f0764782851` |
| channels_hash | `301b0f6dfe70d4c271d5b489e91d53a6` |
| content_hash | `38c3e6f538d463e7ac42ed3b12ea46b6` |
| metrics_hash | `c921c9decaed11583a665503acd580db` |
| make_contract | `9cf0ede290b7d40fcc9073bc3abd3699` |
| roles_hash | `1dcfe8f4402cac673d9b2d6081f496f3` |
| memberships_hash | `9db082a875b3e0118285d5d259efa88f` |
| schemas_hash | `872759d900184a659cbe5b6f2f2d3c2c` |
| database_acl | `ecbc7700df8d1e934b8200d146dcf88d` |
| relations_hash | `d95171e9be8747b90dfca1264fca3f35` |
| functions_hash | `3e2017b51a3ce680be66002384bae67f` |
| views_hash | `99a9d1f30e9bec83b1afc6f3d470d37f` |
| policies_hash | `d41d8cd98f00b204e9800998ecf8427e` |
| columns_hash | `e3e874f486d68d33af4da43c2acece60` |
| constraints_hash | `eb700628755b4e7bb4908d2836de127b` |
| triggers_hash | `526433a8b46d7de31ef9e85f9e83e28b` |

No permanent hosted installation or activation is claimed. At the end of this initial rehearsal-only turn, actual simultaneous-session tests, authenticated hosted settings-save testing, staging deployment, and production rollout remained separate work. The existing local implementation and previously passing local checks were not rerun or modified during that initial turn.

## Subsequent concurrency checks and corrected rehearsal

Later on September 7, the user approved the next concurrency/staging-connection step. Six independent multi-session tests were added and run locally. The activation race exposed dispatch reading the enabled flag before obtaining the shared lock; migration 039 was corrected to select the path only after that lock. All six tests then passed, including activation and deactivation races, stale-save rejection, concurrent generation idempotency, save-versus-generation rejection, and committed revision visibility. All uniquely created test databases were removed; the original local disposable database still contains zero posts/proposals and disabled revision 1 settings.

Corrected migration SHA-256: `8dd7babfcabf54248384ae72b0a91bc6fd087d96ed5c6804423cd9e6fa36e8d0`.
Corrected rehearsal SHA-256: `0eb08f9b4fd360241ca6598c6aa8e1a4758874834cf5d7da10c1e223bbc51ccb`.

The corrected hosted staging rehearsal completed successfully at the same `after_rollback` result. An independent repeat of the audit returned every value in the table above unchanged. Local full 039/038 regression checks, all 179 web tests, production build/TypeScript, ESLint and the security scan passed again.

The subsequent persistent staging installation action was rejected by automatic approval review before execution because it requires explicit authority for its permanent tables, role and grants. No workaround was attempted. Staging remains uninstalled, and no credential was provisioned or deployment performed. Private credential helper files are prepared locally only.
