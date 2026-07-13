-- Creator Analytics
-- Dashboard-ready views
-- File: Database/005_dashboard_views.sql
--
-- These views keep dashboard queries simple while preserving the original
-- tables as the source of truth. Safe to rerun.

begin;

create or replace view public.latest_post_metrics
with (security_invoker = true)
as
select distinct on (m.buffer_post_id)
  m.buffer_post_id,
  m.captured_on,
  m.captured_at,
  m.metrics_updated_at,
  m.views,
  m.reactions,
  m.comments,
  m.shares,
  m.saves,
  m.reach,
  m.impressions,
  m.clicks,
  m.engagement_rate,
  m.watch_time_seconds,
  m.average_view_duration_seconds,
  m.average_percentage_viewed,
  m.followers_gained,
  m.raw_metrics
from public.post_metric_snapshots m
order by
  m.buffer_post_id,
  m.captured_at desc;

create or replace view public.dashboard_posts
with (security_invoker = true)
as
with prepared as (
  select
    p.*,
    ch.service as platform,
    ch.name as channel_name,
    ch.display_name as channel_display_name,
    coalesce(ch.timezone, 'America/Denver') as channel_timezone,
    coalesce(p.sent_at, p.due_at, p.buffer_created_at) as published_at_utc,
    timezone(
      coalesce(ch.timezone, 'America/Denver'),
      coalesce(p.sent_at, p.due_at, p.buffer_created_at)
    ) as published_at_local
  from public.posts p
  join public.channels ch
    on ch.buffer_channel_id = p.buffer_channel_id
)
select
  p.buffer_post_id,
  p.buffer_organization_id,
  p.buffer_channel_id,
  p.content_item_id,
  p.platform,
  p.channel_name,
  p.channel_display_name,
  p.channel_timezone,
  p.status,
  p.post_text,
  p.external_link,
  p.buffer_created_at,
  p.due_at,
  p.sent_at,
  p.published_at_utc,
  p.published_at_local,
  extract(isodow from p.published_at_local)::smallint as publish_iso_day,
  trim(to_char(p.published_at_local, 'Day')) as publish_day_name,
  extract(hour from p.published_at_local)::smallint as publish_hour,
  extract(minute from p.published_at_local)::smallint as publish_minute,
  case
    when p.content_item_id is null then 'unlabeled'
    else 'labeled'
  end as label_status,
  ci.internal_title,
  ci.game,
  ci.content_type,
  ci.vibe,
  ci.hook_type,
  ci.duration_seconds,
  ci.editing_intensity,
  ci.source_recording,
  ci.notes as content_notes,
  lm.captured_on as latest_metric_date,
  lm.captured_at as latest_metric_captured_at,
  lm.metrics_updated_at,
  lm.views,
  lm.reactions,
  lm.comments,
  lm.shares,
  lm.saves,
  lm.reach,
  lm.impressions,
  lm.clicks,
  lm.engagement_rate,
  lm.watch_time_seconds,
  lm.average_view_duration_seconds,
  lm.average_percentage_viewed,
  lm.followers_gained,
  case
    when lm.views is null or lm.views = 0 then null
    else round(
      (
        coalesce(lm.reactions, 0)
        + coalesce(lm.comments, 0)
        + coalesce(lm.shares, 0)
        + coalesce(lm.saves, 0)
      )::numeric * 100 / lm.views,
      4
    )
  end as calculated_interaction_rate,
  p.first_seen_at,
  p.last_synced_at,
  p.created_at,
  p.updated_at
from prepared p
left join public.content_items ci
  on ci.id = p.content_item_id
left join public.latest_post_metrics lm
  on lm.buffer_post_id = p.buffer_post_id;

create or replace view public.posting_time_summary
with (security_invoker = true)
as
select
  platform,
  channel_name,
  publish_iso_day,
  publish_day_name,
  publish_hour,
  count(*)::bigint as post_count,
  round(avg(views)::numeric, 2) as average_views,
  percentile_cont(0.5) within group (order by views) as median_views,
  round(avg(reactions)::numeric, 2) as average_reactions,
  round(avg(comments)::numeric, 2) as average_comments,
  round(avg(shares)::numeric, 2) as average_shares,
  round(avg(engagement_rate)::numeric, 4) as average_buffer_engagement_rate,
  round(avg(calculated_interaction_rate)::numeric, 4)
    as average_calculated_interaction_rate
from public.dashboard_posts
where status = 'sent'
  and published_at_local is not null
  and views is not null
group by
  platform,
  channel_name,
  publish_iso_day,
  publish_day_name,
  publish_hour;

create or replace view public.content_performance_summary
with (security_invoker = true)
as
select
  platform,
  game,
  content_type,
  vibe,
  hook_type,
  count(*)::bigint as post_count,
  round(avg(views)::numeric, 2) as average_views,
  percentile_cont(0.5) within group (order by views) as median_views,
  round(avg(reactions)::numeric, 2) as average_reactions,
  round(avg(comments)::numeric, 2) as average_comments,
  round(avg(shares)::numeric, 2) as average_shares,
  round(avg(engagement_rate)::numeric, 4) as average_buffer_engagement_rate,
  round(avg(calculated_interaction_rate)::numeric, 4)
    as average_calculated_interaction_rate
from public.dashboard_posts
where status = 'sent'
  and content_item_id is not null
  and views is not null
group by
  platform,
  game,
  content_type,
  vibe,
  hook_type;

revoke all on public.latest_post_metrics from public, anon, authenticated;
revoke all on public.dashboard_posts from public, anon, authenticated;
revoke all on public.posting_time_summary from public, anon, authenticated;
revoke all on public.content_performance_summary from public, anon, authenticated;

grant select on public.latest_post_metrics to service_role;
grant select on public.dashboard_posts to service_role;
grant select on public.posting_time_summary to service_role;
grant select on public.content_performance_summary to service_role;

commit;
