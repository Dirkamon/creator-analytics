-- Creator Analytics
-- Content labeling tools
-- File: Database/006_content_labeling_tools.sql
--
-- Adds:
--   1. A queue of posts that still need content labels.
--   2. A helper function that creates one content item and links one or
--      more Buffer posts to it (for example, the TikTok and YouTube
--      versions of the same clip).
-- Safe to rerun.

begin;

create or replace view public.unlabeled_posts_queue
with (security_invoker = true)
as
select
  d.buffer_post_id,
  d.platform,
  d.channel_name,
  d.status,
  d.post_text,
  d.external_link,
  d.published_at_local,
  d.publish_day_name,
  d.publish_hour,
  d.views,
  d.reactions,
  d.comments,
  d.shares,
  d.engagement_rate,
  d.latest_metric_date
from public.dashboard_posts d
where d.content_item_id is null;

create or replace function public.create_content_item_and_link_posts(
  p_post_ids text[],
  p_internal_title text,
  p_game text,
  p_content_type text,
  p_vibe text,
  p_hook_type text default null,
  p_duration_seconds numeric default null,
  p_editing_intensity text default null,
  p_source_recording text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_content_item_id uuid;
  v_requested_count integer;
  v_found_count integer;
  v_already_linked_count integer;
begin
  if p_post_ids is null or cardinality(p_post_ids) = 0 then
    raise exception 'At least one Buffer post ID is required';
  end if;

  select count(distinct post_id)
  into v_requested_count
  from unnest(p_post_ids) as post_id;

  if v_requested_count <> cardinality(p_post_ids) then
    raise exception 'Duplicate Buffer post IDs were supplied';
  end if;

  select count(*)
  into v_found_count
  from public.posts
  where buffer_post_id = any(p_post_ids);

  if v_found_count <> v_requested_count then
    raise exception
      'One or more Buffer post IDs do not exist. Requested %, found %',
      v_requested_count,
      v_found_count;
  end if;

  select count(*)
  into v_already_linked_count
  from public.posts
  where buffer_post_id = any(p_post_ids)
    and content_item_id is not null;

  if v_already_linked_count > 0 then
    raise exception
      'One or more selected posts are already linked to a content item';
  end if;

  insert into public.content_items (
    internal_title,
    game,
    content_type,
    vibe,
    hook_type,
    duration_seconds,
    editing_intensity,
    source_recording,
    notes
  )
  values (
    nullif(btrim(p_internal_title), ''),
    nullif(btrim(p_game), ''),
    nullif(btrim(p_content_type), ''),
    nullif(btrim(p_vibe), ''),
    nullif(btrim(p_hook_type), ''),
    p_duration_seconds,
    nullif(btrim(p_editing_intensity), ''),
    nullif(btrim(p_source_recording), ''),
    nullif(btrim(p_notes), '')
  )
  returning id into v_content_item_id;

  update public.posts
  set
    content_item_id = v_content_item_id,
    updated_at = now()
  where buffer_post_id = any(p_post_ids);

  return v_content_item_id;
end;
$$;

revoke all on public.unlabeled_posts_queue
  from public, anon, authenticated;

grant select on public.unlabeled_posts_queue
  to service_role;

revoke execute
  on function public.create_content_item_and_link_posts(
    text[], text, text, text, text, text, numeric, text, text, text
  )
  from public;

revoke execute
  on function public.create_content_item_and_link_posts(
    text[], text, text, text, text, text, numeric, text, text, text
  )
  from anon, authenticated;

grant execute
  on function public.create_content_item_and_link_posts(
    text[], text, text, text, text, text, numeric, text, text, text
  )
  to service_role;

commit;
