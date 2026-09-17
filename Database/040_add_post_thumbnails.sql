-- Buffer-hosted still images for Recent Performance. No copied media, new
-- credentials, changes to public reporting views, or scheduling writes.
-- Requires 033 and the existing post-sync RPC (003), which already stores the
-- complete post node in raw_data. Make must request assets { thumbnail }.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Follow 036's hosted-Supabase ownership handoff. Only the migration session
-- temporarily receives schema creation access; remove it before committing.
grant creator_analytics_web_view_owner to current_user
with set true, inherit false;
set local role creator_analytics_web_view_owner;
grant usage, create on schema creator_app to session_user;
reset role;

-- A narrow definer projection avoids granting the web roles raw_data access.
create or replace function creator_app.read_post_thumbnails()
returns table (buffer_post_id text, thumbnail_url text)
language sql stable security definer set search_path = ''
as $function$
  select p.buffer_post_id, chosen.thumbnail_url
  from public.posts p
  cross join lateral (
    select asset.value ->> 'thumbnail' as thumbnail_url
    from pg_catalog.jsonb_array_elements(
      case when pg_catalog.jsonb_typeof(p.raw_data -> 'assets') = 'array'
        then p.raw_data -> 'assets' else '[]'::jsonb end
    ) with ordinality as asset(value, position)
    where pg_catalog.jsonb_typeof(asset.value -> 'thumbnail') = 'string'
      and length(asset.value ->> 'thumbnail') <= 4096
      and (asset.value ->> 'thumbnail') ~ '^https://images[.]buffer[.]com/thumbnail/[^/?#[:space:]]+'
    order by asset.position
    limit 1
  ) chosen
  where p.status = 'sent';
$function$;

revoke all on function creator_app.read_post_thumbnails()
from public, anon, authenticated, service_role, creator_dashboard_reader,
  creator_analytics_web_reader;
grant execute on function creator_app.read_post_thumbnails()
to creator_analytics_web_view_owner, creator_analytics_web_reader;
-- PostgreSQL checks function EXECUTE against the invoking reader even through
-- a definer view. This helper exposes only the same two read-only columns.

set local role creator_analytics_web_view_owner;

create or replace view creator_app.post_thumbnails
with (security_invoker = false, security_barrier = true)
as select buffer_post_id, thumbnail_url from creator_app.read_post_thumbnails();

revoke all on creator_app.post_thumbnails
from public, anon, authenticated, service_role, creator_dashboard_reader,
  creator_analytics_web_reader;
grant select on creator_app.post_thumbnails to creator_analytics_web_reader;
comment on view creator_app.post_thumbnails is
'Server-only Buffer post ID and hosted static thumbnail URL, without the raw media payload or video playback.';
revoke usage, create on schema creator_app from session_user;
reset role;
revoke creator_analytics_web_view_owner from current_user granted by current_user;

commit;
