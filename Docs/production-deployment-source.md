# Production deployment source

## Canonical environment

- Production project: Vercel `creator-analytics`.
- Production dashboard: https://creator-analytics-theta.vercel.app/dashboard
- Automatic production source: `main`, application root `apps/web`.
- Staging is a separate Vercel project and Supabase database. Its synthetic data
  is not a live report; do not use its dashboard as a production bookmark.

## September 13, 2026 restoration

The September 7 production release used tested commit
`1ce0af92d4e767ee815729e1c905db25dc2c5b30` from
`staging/scheduling-preferences`. Its interface included themes, the calendar,
controlled schedule decisions, and scheduling preferences. These changes had
not been incorporated into the automatic production branch.

On September 8, README-only commit
`f095efc3a18f76b70b5ddbca3b0d192e0a9f8fcc` on `main` triggered production
deployment `6z56mvYcMMsu2EsWfBM6imJfKDN4`. Because that branch still contained
the older application, it replaced the newer interface. The production database
continued receiving data. On September 13 the production site showed 1,037 sent
posts, metrics through September 13, and seven upcoming posts.

The repair merges the previously tested release into current `main`, preserving
the README commit. Application source is identical to the September 7 tested
release; dependencies and lockfile are unchanged. No SQL migration is executed,
no data or scheduling settings are saved, and no Make scenario is run or edited.
Existing production configuration and restricted credentials are retained.

Validation before publication: 195 tests in 38 files, ESLint, Next.js production
build with TypeScript, security scan of 137 source/configuration files, and eight
signed-out Chromium checks passed. The isolated build used placeholder values
and no production database credentials. `apps/web` has no diff from the tested
release, and `README.md` has no diff from the current production branch.

## Release discipline

1. Incorporate an approved, validated release into `main` before treating it as
   the durable production source. Preserve intervening changes on `main`.
2. Check tests, lint, the production build, and the security scan before pushing
   the production update. Do not force-push or bypass branch protections.
3. Verify Vercel's production source commit matches the intended release.
4. Verify the authenticated dashboard, calendar, upcoming posts, and preference
   readback on the stable production domain. Do not submit mutations merely to
   smoke-test a release. Verify signed-out access separately with test data.
5. Feature-branch previews and manually promoted releases do not synchronize
   `main`. If an emergency promotion is required, reconcile the release with
   `main` before the next automatic production deployment.

Do not change the production branch to a staging branch, copy staging secrets
into production, or rerun database migrations to repair a frontend mismatch.
