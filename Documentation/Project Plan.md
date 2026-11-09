# Creator Analytics project plan

Updated: **November 9, 2026**. See [project progress](<Project Progress.md>) for the dated checklist and evidence boundaries.

## Goal

Provide a usable Windows desktop workflow for gaming clips, preserving content labels, Clip Groups, analytics and explainable scheduling decisions while replacing Make incrementally and keeping costs low.

## Immediate milestone

A user selects a real clip, applies the original labels, reviews and approves a scheduling recommendation, then the app automatically delivers it through R2 to Buffer and independently confirms its status. A second clip must demonstrate repeatable use.

## Ordered next steps

1. Recover expired access through a current, bounded setup while reusing the verified business installation and history.
2. Complete desktop authentication, certificate checks and Buffer consent.
3. Verify current R2 permissions, capacity, retention and delivery.
4. Establish exclusive writer ownership and control conflicting Make actions.
5. Complete first and repeat real-clip acceptance.

Local development tests and an installed backend are intermediate evidence. Release acceptance requires actual provider and canonical results.

## Constraints

- Preserve labels, analytics definitions, scheduling rules, decisions, mappings and recovery history.
- Keep explicit human approval before publishing or schedule changes.
- Use existing free services; no new paid software, subscriptions, domains or upgrades.
- Keep the publishing workflow usable when the desktop is shut down after acceptance.
- Replace Make scenario by scenario; do not require all eight retirements before the first usable release.

## Later work

After the core workflow is accepted, continue replacing the remaining Make scenarios and improve reporting and operator experience. Direct platform analytics, additional platforms such as Instagram and Twitch, and AI-assisted analysis remain later ideas.

The established stack in this repository uses Buffer, Make, Supabase, Sheets, Looker Studio and the private web app. The desktop migration is developed separately; its intended storage and delivery path adds R2 while retaining Buffer publishing and the existing business rules.
