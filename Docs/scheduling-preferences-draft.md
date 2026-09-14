# Scheduling preferences — first design slice

> This records the earlier illustration-only slice. The subsequent local scheduler/form implementation and paused hosted-staging rehearsal are documented in [scheduling-preferences-staging-handoff.md](scheduling-preferences-staging-handoff.md). No hosted preferences rollout has occurred.

## User's posting goal, September 7, 2026

- Two posts per day on average on **each** of TikTok and YouTube Shorts: target 14 per platform per week, 28 platform posts total.
- Flexible distribution: one on Monday and three on Tuesday is acceptable. Two is not an exact daily requirement.
- Cover every day with at least one eligible post **per platform** before allocating extra posts using analytics.
- Initial proposed ceiling: three per platform per day, inferred from the user's example and explicitly disclosed. It remains a draft, not a deployed setting.
- Coverage requires at least seven available eligible platform posts and a safe slot every day. Do not invent clips, weaken protected windows, or override collision safeguards to promise coverage.
- Keep manual approval. Existing applied posts must not be regenerated or moved automatically.
- Posting hours: the user has no preferred time window; performance evidence should drive suggestions. The draft allows all 24 hours, including overnight, in America/Denver. Daily coverage, spacing, fixed reservations, and approval still apply. This choice does not itself remove any current live restrictions.
- Rescheduling limit: the user's "12 hours" answer is interpreted and disclosed as up to 12 hours earlier **or** later than the time they manually set in Buffer, per platform post. The draft anchors the limit to that manual time so repeated proposals cannot accumulate larger moves. Daily coverage is a goal inside this hard limit, not permission to exceed it. Existing applied posts stay untouched.

## Implemented in this slice

Development-only `/design-preview?view=scheduling-preferences`, using the existing three themes and navigation. Independent editable weekly target and daily ceiling per platform; minimum one/day is fixed to the stated requirement. Clearly labeled example inventory and synthetic day preferences demonstrate coverage-first counts and stock/capacity shortfalls. Reset restores the agreed starting point.

The page has no save endpoint, database calls, browser storage, or scheduling actions. Its in-memory values reset when unmounted. The example is not the real SQL scheduler and does not model dates, recommendation scores, spacing, protected hours, channel identity, or slot eligibility. Production does not expose the preview route or its navigation entry.

## Before implementing scheduler changes

1. Posting-hour and movement preferences are settled for the draft: all 24 hours, including overnight, within ±12 elapsed hours of the manually scheduled Buffer timestamp. Inspect how manual baselines are stored and distinguished from syncs of system-applied times; do not re-anchor on each proposal or silently guess missing baselines. Handle deliberate later manual changes explicitly. Preserve current production settings until rollout is explicitly approved; reconcile existing protected-hour settings as part of that reviewed change, not by bypassing safeguards.
2. Resolve the coverage period: the present Make refresh uses a start-date/horizon contract; define which seven local days need coverage without changing the caller contract or bypassing the planning runway.
3. Add versioned settings and a narrow authorized settings write path. Do not broaden the reader, labeler, or schedule-approver credentials into general database writers. Keep the Make-facing view contract intact.
4. Implement coverage-first allocation in the database, **not** by reusing the illustrative TypeScript model. Count fixed/already-applied posts toward each channel's daily floor and capacity; fill uncovered eligible days before optimizing extra placements. Preserve per-post, same-channel spacing, weekly/daily limits, timezone/DST, current-time, history, and protected-window checks.
5. Show unfillable days and why: shortage, no safe slots inside the ±12-hour movement window, stale/missing analytics, missing manual baseline, or fixed reservations. Do not silently extend the movement limit to meet daily coverage, relax spacing, or hide failed reads as an empty queue.
6. Recheck all constraints when approving/applying; handle changed settings and pending proposals explicitly. Never rewrite applied history.
7. Test an isolated staging migration with no Buffer writes: abundant/short/zero inventory; one weak day vs. strong days; unequal platform inventory; occupied slots; protected hours; stale evidence; exact ±12-hour boundaries and just outside them; missing/manual-changed baselines; repeated proposals without cumulative drift; DST/week boundaries; past-time/planning-runway exclusion; concurrent refresh; and repeat-run idempotency. Check existing SQL regressions, auth boundaries, and Make contracts before rollout.

## Unchanged

No production or staging migration, credentials, hosting, Make schedules, Buffer posts, labels, approvals, or live schedules are changed by this slice. Local preview is the handoff; connecting it to the actual scheduler is a separate next stage.

## Verification for this slice

- 151 unit/component tests across 34 files passed after the 12-hour movement-limit update, including coverage/capacity/stock invariants, input validation, independent platform controls, reset, honest shortage states, preview-only navigation, clear draft-only all-hours guidance, and movement-limit/approval language. These are preview tests, not proof of enforcement by the real scheduler. The production build/TypeScript check also passed again.
- Full ESLint pass, targeted lint after final test edits, production build/TypeScript, and security scan (127 source/configuration files) passed.
- Local development preview returned HTTP 200; the same preview URL on the local production build returned 404.
- No browser interaction/visual QA was performed in this slice. Existing theme tokens and responsive components were reused; the user-facing preview was opened for review.
- Retained local preview: `http://127.0.0.1:3107/design-preview?view=scheduling-preferences`. The temporary production-check server on 3108 was stopped. No deployment occurred.
