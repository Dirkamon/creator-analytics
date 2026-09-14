# Scheduling preferences installed in staging — September 7, 2026

## Authority and result

The user explicitly approved adding the new database tables and restricted settings account in staging, leaving the new rules disabled and production untouched. Used the same signed-in Supabase staging editor after verifying **Creator Analytics Staging**, project `iepwctcayajdpvsmfmgl`. No alternate interface bypassed the earlier approval-review pause.

Installed migration `Database/039_add_scheduling_preferences.sql`, SHA-256 `8dd7babfcabf54248384ae72b0a91bc6fd087d96ed5c6804423cd9e6fa36e8d0`, inside one guarded transaction. The wrapper refused existing preference objects/account, non-demo inventory, unexpected counts or Make contract. Before COMMIT it checked disabled revision 1, unchanged full post/proposal/cadence records, preserved old memberships, exact new management membership, safe NOLOGIN role attributes, RLS and the 19-column Make contract.

The successful final installation result was:

```json
{"posts":25,"enabled":false,"revision":1,"installed":true,"proposals":4,"coverage_rows":88,"settings_rows":2,"scheduler_login":false}
```

No proposal refresh, approval, rejection, label change, Buffer call, Make scenario action, Google Sheet write, production change, password creation, source commit/push or app deployment occurred. One new manual baseline was captured for a history-free scheduled staging post; no existing post row changed. Zero settings audit entries exist because no settings save ran.

## Preservation guard correction

The first guarded installation failed and rolled back because Supabase automatically created an account-management membership when postgres created the new role. A rollback-only diagnostic proved posts, proposals and cadence all matched, and the sole new membership was:

```json
{"role":"creator_analytics_web_scheduler","member":"postgres","grantor":"supabase_admin","admin":true,"set":false,"inherit":false}
```

The revised installation guard still compares every old membership exactly, and permits only that exact new ADMIN-only management grant; no SET ROLE or inherited settings privileges are accepted. Both private credential SQL scripts enforce the same strict allowance. A wrapper-formatting error was corrected without running any installation. The complete corrected guard passed a rollback-only run before the permanent installation was retried successfully.

## Independent post-install verification

A separate read-only check passed the entire credential preflight (without changing login or setting a password), confirmed no excessive settings table/function permissions for anon, authenticated, service_role, dashboard reader, web reader, labeler or approver, verified the web reader's two SELECT grants, checked reporting-view ownership and RLS on all three new tables, then returned:

| Check | Result |
| --- | --- |
| New behavior | Disabled, revision 1 |
| New account | NOLOGIN, no password, no dangerous attributes |
| Existing role attributes | Unchanged: `1dcfe8f4402cac673d9b2d6081f496f3` |
| Existing memberships | Unchanged: `9db082a875b3e0118285d5d259efa88f` |
| Posts | Unchanged: `74a242b590f616280bad190be380deca` |
| Proposals, excluding two new null fields | Unchanged: `8a36f7f9773d38bff6b2cf7acf5fd33b` |
| Cadence | Unchanged: `4bc1865c45fa66ccbd35ad187db4ac7f` |
| Organizations | Unchanged: `895ef3d55e40ee808e1b0f0764782851` |
| Channels | Unchanged: `301b0f6dfe70d4c271d5b489e91d53a6` |
| Content items | Unchanged: `38c3e6f538d463e7ac42ed3b12ea46b6` |
| Metric snapshots | Unchanged: `c921c9decaed11583a665503acd580db` |
| Make view definition | Unchanged: `9cf0ede290b7d40fcc9073bc3abd3699` |
| Settings audit entries | 0 |
| Manual baseline entries | 1 |

## Next user action

Run the existing parent-workspace `Setup-Staging-Scheduling-Settings.ps1` privately. `-CheckFilesOnly` passed again. First enter the existing **staging** postgres database administrator password, then create a new unique scheduler password twice and re-enter it for restricted-login verification. The script copies only the verified staging connection URL; do not put secrets in chat. If already provisioned, use `-VerifyOnly` and do not reset the password.

Only after that credential is saved in the **creator-analytics-staging** Vercel project can the staging page be connected, deployed and tested end-to-end. Existing unresolved demo approvals still block a settings save intentionally. Production rollout is not approved by this staging-installation authorization.
