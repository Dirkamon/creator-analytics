# Staging Demo Data

`Database/Seeds/001_staging_demo_data.sql` is a repeatable synthetic fixture
for validating the private read-only web interface. It is not a migration and
must never be applied to production.

## Safety boundary

- Approved target: `Creator Analytics Staging`
- Approved project ref: `iepwctcayajdpvsmfmgl`
- Production is out of scope.
- The seed does not call Buffer, Make, Google Sheets, or any external API.
- All inserted post and channel identifiers begin with `__STAGING_DEMO__`.
- All inserted content and proposal UUIDs use the dedicated `d3e0` namespace.
- Rerunning the seed replaces only its own synthetic rows.

The SQL refuses to run unless the current database session explicitly sets:

```sql
set creator_analytics.seed_target = 'iepwctcayajdpvsmfmgl';
```

After confirming the staging project identity, run that statement and the seed
in the same database session.

## Expected coverage

The fixture creates:

- nine synthetic clip groups represented on TikTok and YouTube;
- eighteen labeled historical posts with two metric snapshots each;
- two additional unlinked historical posts;
- five upcoming posts, including one unlinked post and one unevaluated post;
- Pending, Approved, and Error schedule-proposal examples;
- recent sync and metric timestamps for System Status freshness checks;
- enough repeated day/time samples to exercise recommendations and weekly slots.

The web application remains read-only. Proposal examples are display records
only and do not change any Buffer schedule.
