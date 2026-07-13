-- Creator Analytics
-- Read-only reporting access for Looker Studio
-- File: Database/010_looker_reporting_access.sql
--
-- Creates:
--   1. A dedicated read-only login role for Looker Studio.
--   2. Public reporting views that expose only dashboard-safe columns.
--
-- IMPORTANT:
-- This file intentionally does NOT set a password.
-- Set the password separately in Supabase SQL Editor and do not save that
-- password in GitHub, project files, screenshots, or chat.
-- Safe to rerun.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    create role creator_dashboard_reader
      login
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit;
  end if;
end
$$;

alter role creator_dashboard_reader
  set statement_timeout = '120s';

alter role creator_dashboard_reader
  set default_transaction_read_only = on;

-- Reporting view for one row per Buffer post with latest metrics.
-- This view intentionally runs with the view owner's permissions so the
-- dedicated reader does not need direct SELECT access to the source tables.
create or replace view public.looker_dashboard_posts
with (security_invoker = false)
as
select
  buffer_post_id,
  platform,
  channel_name,
  status,
  post_text,
  external_link,
  published_at_utc,
  published_at_local,
  publish_iso_day,
  publish_day_name,
  publish_hour,
  publish_minute,
  label_status,
  internal_title as clip_group,
  game,
  content_type,
  vibe,
  hook_type,
  duration_seconds,
  editing_intensity,
  latest_metric_date,
  views,
  reactions,
  comments,
  shares,
  saves,
  reach,
  impressions,
  clicks,
  engagement_rate,
  calculated_interaction_rate
from public.dashboard_posts;

-- Posting-time rollup.
create or replace view public.looker_posting_time_summary
with (security_invoker = false)
as
select *
from public.posting_time_summary;

-- Content performance rollup.
create or replace view public.looker_content_performance_summary
with (security_invoker = false)
as
select *
from public.content_performance_summary;

-- Daily metric gains. The first snapshot for each post is excluded so
-- historical cumulative totals are not misread as one day's growth.
create or replace view public.looker_daily_growth
with (security_invoker = false)
as
with post_deltas as (
  select
    p.channel_service as platform,
    m.buffer_post_id,
    m.captured_on,
    m.views,
    m.reactions,
    m.comments,
    m.shares,
    lag(m.views) over (
      partition by m.buffer_post_id
      order by m.captured_on
    ) as previous_views,
    lag(m.reactions) over (
      partition by m.buffer_post_id
      order by m.captured_on
    ) as previous_reactions,
    lag(m.comments) over (
      partition by m.buffer_post_id
      order by m.captured_on
    ) as previous_comments,
    lag(m.shares) over (
      partition by m.buffer_post_id
      order by m.captured_on
    ) as previous_shares
  from public.post_metric_snapshots m
  join public.posts p
    on p.buffer_post_id = m.buffer_post_id
)
select
  platform,
  captured_on,
  sum(greatest(coalesce(views - previous_views, 0), 0))::bigint
    as views_gained,
  sum(greatest(coalesce(reactions - previous_reactions, 0), 0))::bigint
    as reactions_gained,
  sum(greatest(coalesce(comments - previous_comments, 0), 0))::bigint
    as comments_gained,
  sum(greatest(coalesce(shares - previous_shares, 0), 0))::bigint
    as shares_gained
from post_deltas
where previous_views is not null
group by platform, captured_on;

revoke all on public.looker_dashboard_posts
  from public, anon, authenticated;
revoke all on public.looker_posting_time_summary
  from public, anon, authenticated;
revoke all on public.looker_content_performance_summary
  from public, anon, authenticated;
revoke all on public.looker_daily_growth
  from public, anon, authenticated;

grant connect on database postgres
  to creator_dashboard_reader;

grant usage on schema public
  to creator_dashboard_reader;

grant select on public.looker_dashboard_posts
  to creator_dashboard_reader;
grant select on public.looker_posting_time_summary
  to creator_dashboard_reader;
grant select on public.looker_content_performance_summary
  to creator_dashboard_reader;
grant select on public.looker_daily_growth
  to creator_dashboard_reader;

commit;
