-- Creator Analytics
-- Joint day-and-time posting recommendations
-- File: Database/014_joint_posting_recommendations.sql
--
-- Creates a recommendation model that evaluates the day and time window
-- together, rather than combining the best day and best time independently.
-- Safe to rerun.

begin;

create or replace view public.looker_joint_posting_recommendations
with (security_invoker = false)
as
with base as (
  select
    platform,
    publish_iso_day,
    publish_day_name,
    publish_hour,
    case
      when publish_hour between 0 and 3 then 0
      when publish_hour between 4 and 7 then 4
      when publish_hour between 8 and 11 then 8
      when publish_hour between 12 and 15 then 12
      when publish_hour between 16 and 19 then 16
      when publish_hour between 20 and 23 then 20
    end as window_start_hour,
    case
      when publish_hour between 0 and 3 then 3
      when publish_hour between 4 and 7 then 7
      when publish_hour between 8 and 11 then 11
      when publish_hour between 12 and 15 then 15
      when publish_hour between 16 and 19 then 19
      when publish_hour between 20 and 23 then 23
    end as window_end_hour,
    case
      when publish_hour between 0 and 3 then '12 AM–3:59 AM'
      when publish_hour between 4 and 7 then '4 AM–7:59 AM'
      when publish_hour between 8 and 11 then '8 AM–11:59 AM'
      when publish_hour between 12 and 15 then '12 PM–3:59 PM'
      when publish_hour between 16 and 19 then '4 PM–7:59 PM'
      when publish_hour between 20 and 23 then '8 PM–11:59 PM'
    end as time_window,
    views::numeric as views,
    coalesce(calculated_interaction_rate, 0)::numeric
      as calculated_interaction_rate,
    latest_metric_date
  from public.looker_dashboard_posts
  where status = 'sent'
    and published_at_local is not null
    and publish_iso_day is not null
    and publish_day_name is not null
    and publish_hour is not null
    and views is not null
    and views > 0
),
platform_baseline as (
  select
    platform,
    count(*)::integer as platform_post_count,
    avg(views)::numeric as platform_avg_views,
    avg(calculated_interaction_rate)::numeric
      as platform_avg_interaction_rate,
    max(latest_metric_date) as platform_latest_metric_date
  from base
  group by platform
),
grouped as (
  select
    platform,
    publish_iso_day,
    publish_day_name,
    window_start_hour,
    window_end_hour,
    time_window,
    count(*)::integer as post_count,
    avg(views)::numeric as avg_views,
    percentile_cont(0.5) within group (order by views)::numeric
      as median_views,
    avg(calculated_interaction_rate)::numeric
      as avg_interaction_rate,
    max(latest_metric_date) as latest_metric_date
  from base
  group by
    platform,
    publish_iso_day,
    publish_day_name,
    window_start_hour,
    window_end_hour,
    time_window
),
adjusted as (
  select
    g.*,
    p.platform_post_count,
    p.platform_avg_views,
    p.platform_avg_interaction_rate,

    -- Stronger prior than the day-only or time-only model because joint
    -- day/time buckets are more granular and can have smaller samples.
    (
      (g.post_count * g.avg_views)
      + (8 * p.platform_avg_views)
    ) / (g.post_count + 8) as adjusted_avg_views,

    (
      (g.post_count * g.avg_interaction_rate)
      + (8 * p.platform_avg_interaction_rate)
    ) / (g.post_count + 8) as adjusted_interaction_rate,

    current_date - p.platform_latest_metric_date as metrics_age_days
  from grouped g
  join platform_baseline p using (platform)
),
scored as (
  select
    a.*,
    (
      (
        0.65 * percent_rank() over (
          partition by platform
          order by adjusted_avg_views
        )
        + 0.20 * percent_rank() over (
          partition by platform
          order by adjusted_interaction_rate
        )
        + 0.15 * percent_rank() over (
          partition by platform
          order by post_count
        )
      ) * 100
    )::numeric(6,1) as recommendation_score
  from adjusted a
),
ranked as (
  select
    s.*,
    row_number() over (
      partition by platform
      order by
        recommendation_score desc,
        post_count desc,
        publish_iso_day asc,
        window_start_hour asc
    )::integer as recommendation_rank
  from scored s
)
select
  platform,
  recommendation_rank,
  publish_iso_day,
  publish_day_name,
  window_start_hour,
  window_end_hour,
  time_window,
  publish_day_name || ' · ' || time_window as recommended_slot,
  post_count,
  platform_post_count,
  round(avg_views, 1) as avg_views,
  round(median_views, 1) as median_views,
  round(avg_interaction_rate, 2) as avg_interaction_rate,
  round(adjusted_avg_views, 1) as adjusted_avg_views,
  round(adjusted_interaction_rate, 2) as adjusted_interaction_rate,
  recommendation_score,
  case
    when post_count >= 12 then 'High'
    when post_count >= 7 then 'Medium'
    when post_count >= 4 then 'Low'
    else 'Experimental'
  end as confidence,
  latest_metric_date,
  metrics_age_days,
  case
    when metrics_age_days <= 2 then 'Fresh'
    when metrics_age_days <= 4 then 'Delayed'
    else 'Stale'
  end as metrics_status,
  (
    post_count >= 4
    and metrics_age_days <= 2
  ) as recommendation_ready_for_approval_mode
from ranked;


create or replace view public.looker_joint_posting_recommendation_summary
with (security_invoker = false)
as
select
  platform,
  publish_iso_day as recommended_iso_day,
  publish_day_name as recommended_day,
  window_start_hour as recommended_window_start_hour,
  window_end_hour as recommended_window_end_hour,
  time_window as recommended_time_window,
  recommended_slot,
  post_count as supporting_sample_size,
  recommendation_score,
  confidence,
  avg_views,
  median_views,
  avg_interaction_rate,
  adjusted_avg_views,
  adjusted_interaction_rate,
  metrics_age_days,
  metrics_status,
  recommendation_ready_for_approval_mode
from public.looker_joint_posting_recommendations
where recommendation_rank = 1;


revoke all on public.looker_joint_posting_recommendations
  from public, anon, authenticated;
revoke all on public.looker_joint_posting_recommendation_summary
  from public, anon, authenticated;

grant select on public.looker_joint_posting_recommendations
  to creator_dashboard_reader;
grant select on public.looker_joint_posting_recommendation_summary
  to creator_dashboard_reader;

commit;
