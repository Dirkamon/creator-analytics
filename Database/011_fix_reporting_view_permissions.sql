-- Creator Analytics
-- Fix reporting-view permissions for Data Studio
-- File: Database/011_fix_reporting_view_permissions.sql
--
-- The read-only Data Studio role should only read the public looker_* reporting
-- views. Some internal dashboard views may be SECURITY INVOKER views, which can
-- force the reader role to have permissions on nested views/tables. This
-- migration makes the internal reporting views run with their owner's
-- permissions and keeps them inaccessible to public client roles.
--
-- Safe to rerun.

begin;

alter view public.latest_post_metrics
  set (security_invoker = false);

alter view public.dashboard_posts
  set (security_invoker = false);

alter view public.posting_time_summary
  set (security_invoker = false);

alter view public.content_performance_summary
  set (security_invoker = false);

-- Keep internal views private.
revoke all on public.latest_post_metrics
  from public, anon, authenticated, creator_dashboard_reader;

revoke all on public.dashboard_posts
  from public, anon, authenticated, creator_dashboard_reader;

revoke all on public.posting_time_summary
  from public, anon, authenticated, creator_dashboard_reader;

revoke all on public.content_performance_summary
  from public, anon, authenticated, creator_dashboard_reader;

-- The dashboard reader only needs the curated reporting views.
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
