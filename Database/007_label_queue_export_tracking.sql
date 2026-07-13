-- Creator Analytics
-- Label queue export tracking
-- File: Database/007_label_queue_export_tracking.sql
--
-- Prevents the Make.com queue-population scenario from adding the same
-- Buffer post to Google Sheets more than once.
-- Safe to rerun.

begin;

alter table public.posts
  add column if not exists label_queue_exported_at timestamptz;

create index if not exists posts_label_queue_export_idx
  on public.posts (label_queue_exported_at)
  where content_item_id is null;

create or replace view public.pending_label_queue_exports
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
join public.posts p
  on p.buffer_post_id = d.buffer_post_id
where d.content_item_id is null
  and p.label_queue_exported_at is null;

create or replace function public.mark_label_queue_exported(
  p_post_id text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_updated integer;
begin
  update public.posts
  set
    label_queue_exported_at = now(),
    updated_at = now()
  where buffer_post_id = p_post_id
    and label_queue_exported_at is null;

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$$;

revoke all on public.pending_label_queue_exports
  from public, anon, authenticated;

grant select on public.pending_label_queue_exports
  to service_role;

revoke execute
  on function public.mark_label_queue_exported(text)
  from public;

revoke execute
  on function public.mark_label_queue_exported(text)
  from anon, authenticated;

grant execute
  on function public.mark_label_queue_exported(text)
  to service_role;

commit;
