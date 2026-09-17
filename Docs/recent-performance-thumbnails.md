# Recent Performance thumbnails

## Scope

Reuse Buffer-hosted static thumbnails on Recent Performance. No media upload,
copied storage, AI service, video player, publishing action, or scheduling change.
The browser loads the existing still directly, lazily and without a page referrer.
Buffer's thumbnail URL may contain its source-video URL as a query parameter;
the application does not request that video or expose the full `raw_data` object.

Missing, invalid, or failed images show a stable placeholder. A failed thumbnail
query leaves post metrics available with a partial-data warning. Dashboard and
Top Posts retain their existing queries. URLs must pass both the database
projection and an exact HTTPS-origin/path check in TypeScript; CSP permits only
`https://images.buffer.com` in addition to existing same-origin/data images.

## Deployment order

1. Add `assets { thumbnail }` to the existing Buffer post-sync GraphQL selection.
   Keep all filters, pagination limits, mappings, keychains, and schedules intact.
   The existing `sync_buffer_posts` RPC already saves the complete node.
2. Apply `Database/040_add_post_thumbnails.sql` after migration 033.
3. Run `Tests/Database/040_post_thumbnails_regression.sql` as the migration
   administrator. It rolls back test-only role membership. The web reader gets
   SELECT on a two-column private view and EXECUTE on its read-only helper,
   following 033's function permission model; it gets no base-table access.
4. Deploy the web app from main through the existing Vercel integration.
5. Check real signed-in cards, lazy image loading, metrics, mobile layout, and
   unauthenticated access. The development-only preview must remain unavailable
   in production.

Apply 040 separately to any other database before using thumbnails there. The
web app degrades to placeholders and a warning when that projection is absent.

## Production evidence — September 17, 2026

- Make scenario: `5642633`, Buffer to Supabase - Post Sync, module 2 only.
- Verified successful run: `86ee5bebca3e4b028f9b987c6294a591`.
- Existing fetch limit remains 100 posts. No historical backfill was requested.
- First updated sync stored assets for 100 posts; the restricted projection
  returned 88 usable sent-post thumbnails, zero duplicate IDs, zero other hosts.
- Migration was rehearsed with a rollback, then applied to production project
  `ppgrvebsgefoogulolhs`. Permission checks passed under the restricted reader.
- Existing schedules and approvals were not modified.
- Web validation: 247 tests passed, lint/typecheck/security scan passed, and
  production build passed. Real-image desktop/mobile preview was verified.

Older posts outside the existing sync window may remain without images. Buffer
can also omit a thumbnail or stop serving an old URL. The regular sync refreshes
URLs for posts it returns; failure placeholders do not affect metrics.

## Rollback

Redeploy the previous web release first. The additive private view and helper may
remain without affecting prior pages. If image collection must also stop, remove
only `assets { thumbnail }` from module 2's selection after checking its current
revision. Do not change other scenario fields or revert unrelated edits. No
post, metric, label, or proposal rows need to be deleted.
