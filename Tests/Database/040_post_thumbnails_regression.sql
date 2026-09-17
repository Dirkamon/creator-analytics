-- Read-only assertions after migration 040. No post or metric writes.
begin;
do $test$
begin
  if has_schema_privilege('anon', 'creator_app', 'USAGE')
     or has_schema_privilege('authenticated', 'creator_app', 'USAGE')
     or has_table_privilege('creator_analytics_web_reader', 'public.posts', 'SELECT')
     or has_function_privilege('anon', 'creator_app.read_post_thumbnails()', 'EXECUTE')
     or has_function_privilege('authenticated', 'creator_app.read_post_thumbnails()', 'EXECUTE')
     or has_function_privilege('service_role', 'creator_app.read_post_thumbnails()', 'EXECUTE') then
    raise exception 'Thumbnail read boundary exposed excess privileges';
  end if;
  if not has_table_privilege('creator_analytics_web_reader', 'creator_app.post_thumbnails', 'SELECT')
     or not has_function_privilege('creator_analytics_web_reader', 'creator_app.read_post_thumbnails()', 'EXECUTE')
     or has_table_privilege('creator_analytics_web_reader', 'creator_app.post_thumbnails', 'UPDATE')
     or has_table_privilege('creator_analytics_web_reader', 'creator_app.post_thumbnails', 'INSERT')
     or has_table_privilege('creator_analytics_web_reader', 'creator_app.post_thumbnails', 'DELETE') then
    raise exception 'Thumbnail view is not select-only for the web reader';
  end if;
  if (select array_agg(a.attname::text order by a.attnum)
      from pg_attribute a where a.attrelid = 'creator_app.post_thumbnails'::regclass
      and a.attnum > 0 and not a.attisdropped)
      <> array['buffer_post_id', 'thumbnail_url'] then
    raise exception 'Unexpected columns in thumbnail projection';
  end if;
end;
$test$;

-- Temporary test-session membership is rolled back with the entire probe.
grant creator_analytics_web_reader to current_user with set true, inherit false;
set local role creator_analytics_web_reader;
select count(*) as available_thumbnails,
       count(*) filter (where thumbnail_url !~ '^https://images[.]buffer[.]com/thumbnail/') as unexpected_hosts,
       count(*) - count(distinct buffer_post_id) as duplicate_posts
from creator_app.post_thumbnails;
reset role;
rollback;
