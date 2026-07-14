-- Creator Analytics
-- Grant the Data Studio reader access to nested reporting views
-- File: Database/012_grant_reader_nested_view_access.sql
--
-- This keeps the dashboard account read-only while allowing Data Studio
-- to resolve the full reporting-view chain after refreshes.
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

grant usage on schema public
  to creator_dashboard_reader;

grant select on
  public.latest_post_metrics,
  public.dashboard_posts,
  public.posting_time_summary,
  public.content_performance_summary,
  public.looker_dashboard_posts,
  public.looker_posting_time_summary,
  public.looker_content_performance_summary,
  public.looker_daily_growth
to creator_dashboard_reader;

commit;
