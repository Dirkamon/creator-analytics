# Guardrails and Migration 028

## Evidence labels

- **[Repository-verified]** Directly enforced or represented by migrations 001–028.
- **[Handoff-only]** Operational report supplied only by the handoff.
- **[Inference]** Interpretation or risk analysis.
- **[Live verification required]** Needs production evidence or operator confirmation.

This document distinguishes database-enforced guarantees, procedural safeguards in repository functions, and expectations delegated to Make or Buffer.

## Guardrail matrix

| Guardrail | Repository enforcement after 028 | Boundary or unresolved risk |
| --- | --- | --- |
| Manual approval before Buffer changes | `approved_schedule_changes_ready_to_apply` requires `Approved`; proposal generators only create `Pending`; no SQL function calls Buffer. | **[Live verification required]** Make blueprint must confirm it reads only this view and has no bypass route. A service role or external actor could still mutate Buffer independently. |
| Approximately 24-hour protected window | Short-form seeds use 24 hours. Preview/creation require proposed UTC time beyond protected hours; application-ready view rechecks at read time. | **[Repository-verified]** Setting is configurable, so 24 hours is not immutable. Current due time is not itself rechecked against the window by the application view. |
| Same-platform collision protection | Weekly template enforces per-day limit/gap; hybrid assignment gives unique slots within a platform cadence cycle and checks proposed gaps/day counts. | The application-ready view does not independently recheck collisions after proposal generation. **[Live verification required]** External preflight behavior. |
| One-time schedule evaluation | Effective proposal functions require null evaluation timestamp and no proposal history; successful inserts mark posts evaluated. | No-op/blocked rows are not marked evaluated by effective 027–028 functions. Protection is about proposal history, not necessarily one examination. |
| Active-proposal uniqueness | Partial unique index prevents more than one `Pending`/`Approved` row per `buffer_post_id`. | It is not universal history uniqueness. Other statuses may coexist, and other insert paths could create new non-active history. |
| Proposal-history protection | Effective manual/automatic functions use `NOT EXISTS` over all proposal history plus evaluation lock. | Procedural rather than a table constraint or trigger. A future write path could omit it. |
| Timezone correctness | Named timezone, local and UTC proposal timestamps, `AT TIME ZONE`, Denver metric day, local-date preview generation. | **[Live verification required]** Database/session, Make, Sheet, and Buffer timezone settings and DST boundary tests. |
| Audit-history preservation | Proposal history allowed after migration 019; migration 028 rejects duplicates instead of deleting; decisions/results retain timestamps and messages. | No immutable audit trigger prevents later updates/deletes by privileged roles. External Make/Buffer audit availability is unknown. |

## Manual approval invariant

**[Repository-verified]** Content-aware proposal creation inserts status `Pending`. `set_schedule_proposal_decision` is a separate call. The application-ready view returns only `Approved` rows, and application-result RPCs only update rows currently `Approved`.

**[Repository-verified]** Proposal generation, decision storage, application eligibility, and application-result recording are distinct database operations.

**[Inference]** This is a strong repository boundary, but not proof that every production Buffer mutation passes through it. That depends on Make credentials and scenario configuration.

## Protected-window invariant

**[Repository-verified]** Seeded short-form `protected_hours` is 24. Proposal preview/generation requires the proposed time to remain beyond that duration; application-ready eligibility repeats that check using the current clock.

**[Repository-verified]** The setting can be changed in `scheduling_cadence_settings`, so documentation should say “configured protected window, initially 24 hours,” not “hard-coded 24-hour guarantee.”

**[Inference]** Rechecking at application time protects proposals whose proposed time has moved into the protected window while awaiting approval.

**[Live verification required]** Whether the external scenario also protects the post’s current live Buffer schedule and whether a row disappearing from the ready view is surfaced to the operator.

## Collision and cadence invariant

**[Repository-verified]** The weekly slot generator enforces configured maximum posts per local day and circular same-platform minimum gap. The hybrid scheduler assigns each platform/cadence-cycle slot once, calculates daily counts and previous-proposal gaps, and requires `hybrid_guardrail_status = 'Pass'` for proposal readiness.

**[Repository-verified]** The actual seeded YouTube short-form minimum is four hours, while migration 015’s prose says the minimum is six hours. TikTok is six hours.

**[Repository-verified]** `approved_schedule_changes_ready_to_apply` does not recompute collisions against:

- other approved proposals created later;
- posts newly added or manually rescheduled in Buffer;
- a changed cadence configuration;
- live Buffer queue state.

**[Live verification required]** Whether Make or Buffer supplies a last-mile collision check. Until verified, collision protection is generation-time protection, not an independently revalidated application-time invariant.

## One-time evaluation invariant

### Historical behavior

**[Repository-verified]** Migration 021’s refresh paired future posts with slots and marked every newly paired post evaluated, even if its current time already matched the recommendation and no proposal was inserted.

**[Repository-verified]** Migration 026’s manual content-aware bridge created proposals without marking posts evaluated.

**[Repository-verified]** Migration 027’s automatic content-aware refresh checked `schedule_evaluated_at IS NULL` and marked successful inserts evaluated.

### Effective behavior after migration 028

**[Repository-verified]** Both content-aware creation functions now require:

1. `posts.schedule_evaluated_at IS NULL`; and
2. no row of any status in `schedule_change_proposals` for that post.

Successful inserts set `schedule_evaluated_at`.

**[Repository-verified]** No-op rows are absent from the proposal preview, and blocked/uninserted rows are not marked evaluated by the effective functions.

**[Inference]** The precise invariant is: “Once a post has proposal history, it cannot receive another proposal through the two migration-028 functions.” It is not: “Every scheduled post is examined only once.”

## Active-proposal uniqueness and history protection

**[Repository-verified]** The partial unique index:

```sql
unique (buffer_post_id)
where approval_status in ('Pending', 'Approved')
```

prevents two simultaneously active proposals for one post.

**[Repository-verified]** It permits any number of `Rejected`, `Applied`, or `Error` rows and does not prevent another active row merely because terminal history exists.

**[Repository-verified]** Migration 028’s `NOT EXISTS` history predicate prevents that through the named manual and automatic functions.

**[Inference]** Defense in depth currently consists of:

- post evaluation timestamp;
- all-history function predicate;
- preview active-proposal test;
- partial unique active index.

Only the last item is a database constraint against arbitrary insert callers, and it covers active overlap rather than history reuse.

## Stale schedule risk

**[Repository-verified]** A proposal records `current_due_at_utc/local` at generation time. The application-ready view joins the synchronized post and verifies only that its status is still `scheduled`; it does not compare `posts.due_at` with the captured current time.

**[Inference]** If a schedule changes in Buffer after proposal generation, an approved proposal could still appear ready after post sync, as long as the post remains scheduled and the proposed time is outside the protected window.

**[Live verification required]** Confirm whether Make retrieves and compares Buffer’s current due time immediately before update, whether Buffer supports conditional writes, and how stale proposals are reported.

## Fixed preview calendar risk

**[Repository-verified]** Upstream content-aware shadow views generate local dates from today +2 through today +23. The refresh RPC’s date arguments filter those already-generated rows.

**[Inference]** `p_start_date`/`p_horizon_days` are not the sole calendar-generation authority. Nonstandard parameters can request a range that is only partially represented by the fixed preview.

**[Live verification required]** Exact Make arguments and tests for ranges shorter, longer, earlier, or later than the fixed preview.

## Timezone invariant and uncertainty

**[Repository-verified]** The schema stores `timestamptz` values for absolute time, local timestamps for display/calendar decisions, and timezone names. It converts local schedules with PostgreSQL `AT TIME ZONE`.

**[Repository-verified]** Some functions default `p_start_date` to database `current_date`, while preview views derive dates from `now()` converted to the cadence timezone.

**[Inference]** If the database/session timezone differs from the cadence timezone, default start date and preview-local date can disagree near midnight.

**[Live verification required]** Supabase database and role timezone settings, Make timezone/date serialization, Google Sheets timezone, Buffer channel timezone, and DST transition tests.

## Audit-history invariant

**[Repository-verified]** Migration 019 intentionally permits terminal history. Migration 028 preserves accidental duplicate rows by changing them to Rejected and adding a result message instead of deleting them.

**[Repository-verified]** Proposal rows retain generated, updated, decision, application, result, and error fields.

**[Inference]** This is audit-friendly but not append-only. Security-definer functions and privileged roles can update rows, and no repository trigger records every before/after change.

**[Live verification required]** Retention policy, Supabase database audit facilities, Make execution history, and Buffer activity logs.

## Migration 028 root cause

**[Repository-verified]** Migration 026’s manual `create_content_aware_schedule_proposals` inserted pending proposals but did not update `posts.schedule_evaluated_at`.

**[Repository-verified]** Migration 027’s automatic refresh treated null `schedule_evaluated_at` as eligible and preview logic only blocked active `Pending`/`Approved` proposals.

**[Repository-verified]** Once the migration-026 proposal became terminal—especially `Applied`—it no longer counted as active. The post still had a null evaluation lock, allowing automatic refresh to reconsider it.

**[Inference]** The partial active unique index performed as designed: it prevented concurrent active duplicates, not reuse after a terminal proposal. The defect was a mismatch between the intended one-time lifecycle and the state written by migration 026.

## Migration 028 remediation

**[Repository-verified]** The migration performs three classes of remediation:

1. **Lock backfill:** sets each unlocked post’s evaluation timestamp to its earliest proposal generation time.
2. **Audit-preserving cleanup:** rejects pending proposals that have a strictly earlier terminal proposal for the same post; retains the rows and records a reason.
3. **Function hardening:** replaces both manual and automatic content-aware functions so they require null evaluation state plus no proposal history, then mark successful inserts evaluated.

**[Repository-verified]** It does not call Buffer or modify Buffer schedules.

## Migration 028 reported verification

These are not facts proven by the repository:

- **[Handoff-only]** zero posts with proposal history and missing evaluation lock;
- **[Handoff-only]** zero accidental pending duplicates remaining;
- **[Handoff-only]** 18 accidental duplicates rejected by migration 028;
- **[Handoff-only]** zero old rows created by a controlled refresh;
- **[Handoff-only]** exactly 12 new proposals for 12 fresh labeled posts;
- **[Handoff-only]** no old applied posts resurfaced.

**[Live verification required]** The final 12-post outcome remains unknown because the handoff says application was still pending.

## Regression conditions

The following tests should pass before post-028 behavior is treated as a verified production baseline:

1. **[Live verification required]** Every post with proposal history has a non-null evaluation timestamp.
2. **[Live verification required]** No post has more than one active Pending/Approved proposal.
3. **[Live verification required]** No active proposal exists for a post with an earlier terminal proposal unless explicitly explained as pre-remediation history.
4. **[Live verification required]** Re-running manual and automatic creation produces zero rows for posts with any history, even if evaluation timestamps are cleared in an isolated test database.
5. **[Live verification required]** A genuinely new, labeled, scheduled post outside the window can create exactly one proposal and receives an evaluation timestamp transactionally.
6. **[Live verification required]** Approval alone does not change Buffer; rejection never changes Buffer.
7. **[Live verification required]** Application skips rows that enter the protected window.
8. **[Live verification required]** A stale Buffer current schedule is detected or safely reconciled before update.
9. **[Live verification required]** A new same-platform collision is detected before application.
10. **[Live verification required]** Denver DST spring-forward and fall-back test cases yield intended local and UTC times.
11. **[Live verification required]** The 12 approved proposals become Applied once, have timestamps and no errors, match Buffer, and never reappear on refresh.

## Conditions that could regress the fix

- **[Inference]** Adding a proposal insertion path that omits both history and evaluation checks.
- **[Inference]** Clearing `schedule_evaluated_at` and bypassing repository functions.
- **[Inference]** Removing or weakening the active-proposal partial unique index.
- **[Inference]** Replacing the effective functions with historical migration-026/027 definitions.
- **[Inference]** Treating terminal status as permission for a repeat cycle without explicitly changing the one-proposal-history product invariant.
- **[Inference]** Failing to mark successful inserts evaluated in the same transaction.
- **[Inference]** Assuming the application-ready view performs stale-schedule or collision revalidation when it does not.
