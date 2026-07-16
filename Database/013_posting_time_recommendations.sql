-- Creator Analytics
-- Posting-time recommendation views
-- File: Database/013_posting_time_recommendations.sql
--
-- Creates transparent, read-only recommendation views for Data Studio.
-- Recommendations are calculated separately by platform.
--
-- Important:
-- - Recommended day and recommended time window are estimated independently.
-- - Low-sample groups are shrunk toward the platform average to reduce
--   one-post outliers.
-- - The views include sample size, confidence, and metric freshness so later
--   automations can refuse to reschedule posts when evidence is weak or stale.
-- - Safe to rerun.

begin;

create or replace view public.looker_posting_day_recommendations
with (security_invoker = false)
as
with base as (
  select
    platform,
    publish_iso_day,
    publish_day_name,
    views::numeric as views,
    coalesce(calculated_interaction_rate, 0)::numeric
      as calculated_interaction_rate,
    latest_metric_date
  from public.looker_dashboard_posts
  where status = 'sent'
    and published_at_local is not null
    and publish_iso_day is not null
    and publish_day_name is not null
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
    publish_day_name
),
adjusted as (
  select
    g.*,
    p.platform_post_count,
    p.platform_avg_views,
    p.platform_avg_interaction_rate,
    (
      (g.post_count * g.avg_views)
      + (5 * p.platform_avg_views)
    ) / (g.post_count + 5) as adjusted_avg_views,
    (
      (g.post_count * g.avg_interaction_rate)
      + (5 * p.platform_avg_interaction_rate)
    ) / (g.post_count + 5) as adjusted_interaction_rate,
    current_date - p.platform_latest_metric_date as metrics_age_days
  from grouped g
  join platform_baseline p using (platform)
),
scored as (
  select
    a.*,
    (
      (
        0.70 * percent_rank() over (
          partition by platform
          order by adjusted_avg_views
        )
        + 0.20 * percent_rank() over (
          partition by platform
          order by adjusted_interaction_rate
        )
        + 0.10 * percent_rank() over (
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
        publish_iso_day asc
    )::integer as recommendation_rank
  from scored s
)
select
  platform,
  recommendation_rank,
  publish_iso_day,
  publish_day_name,
  post_count,
  platform_post_count,
  round(avg_views, 1) as avg_views,
  round(median_views, 1) as median_views,
  round(avg_interaction_rate, 2) as avg_interaction_rate,
  round(adjusted_avg_views, 1) as adjusted_avg_views,
  round(adjusted_interaction_rate, 2) as adjusted_interaction_rate,
  recommendation_score,
  case
    when post_count >= 10 then 'High'
    when post_count >= 6 then 'Medium'
    when post_count >= 3 then 'Low'
    else 'Experimental'
  end as confidence,
  latest_metric_date,
  metrics_age_days,
  case
    when metrics_age_days <= 2 then 'Fresh'
    when metrics_age_days <= 4 then 'Delayed'
    else 'Stale'
  end as metrics_status
from ranked;


create or replace view public.looker_time_window_recommendations
with (security_invoker = false)
as
with base as (
  select
    platform,
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
    (
      (g.post_count * g.avg_views)
      + (5 * p.platform_avg_views)
    ) / (g.post_count + 5) as adjusted_avg_views,
    (
      (g.post_count * g.avg_interaction_rate)
      + (5 * p.platform_avg_interaction_rate)
    ) / (g.post_count + 5) as adjusted_interaction_rate,
    current_date - p.platform_latest_metric_date as metrics_age_days
  from grouped g
  join platform_baseline p using (platform)
),
scored as (
  select
    a.*,
    (
      (
        0.70 * percent_rank() over (
          partition by platform
          order by adjusted_avg_views
        )
        + 0.20 * percent_rank() over (
          partition by platform
          order by adjusted_interaction_rate
        )
        + 0.10 * percent_rank() over (
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
        window_start_hour asc
    )::integer as recommendation_rank
  from scored s
)
select
  platform,
  recommendation_rank,
  window_start_hour,
  window_end_hour,
  time_window,
  post_count,
  platform_post_count,
  round(avg_views, 1) as avg_views,
  round(median_views, 1) as median_views,
  round(avg_interaction_rate, 2) as avg_interaction_rate,
  round(adjusted_avg_views, 1) as adjusted_avg_views,
  round(adjusted_interaction_rate, 2) as adjusted_interaction_rate,
  recommendation_score,
  case
    when post_count >= 10 then 'High'
    when post_count >= 6 then 'Medium'
    when post_count >= 3 then 'Low'
    else 'Experimental'
  end as confidence,
  latest_metric_date,
  metrics_age_days,
  case
    when metrics_age_days <= 2 then 'Fresh'
    when metrics_age_days <= 4 then 'Delayed'
    else 'Stale'
  end as metrics_status
from ranked;


create or replace view public.looker_posting_recommendation_summary
with (security_invoker = false)
as
with best_day as (
  select *
  from public.looker_posting_day_recommendations
  where recommendation_rank = 1
),
best_window as (
  select *
  from public.looker_time_window_recommendations
  where recommendation_rank = 1
)
select
  d.platform,
  d.publish_iso_day as recommended_iso_day,
  d.publish_day_name as recommended_day,
  d.post_count as day_sample_size,
  d.recommendation_score as day_score,
  d.confidence as day_confidence,
  w.window_start_hour as recommended_window_start_hour,
  w.window_end_hour as recommended_window_end_hour,
  w.time_window as recommended_time_window,
  w.post_count as window_sample_size,
  w.recommendation_score as window_score,
  w.confidence as window_confidence,
  least(d.post_count, w.post_count) as minimum_supporting_sample,
  greatest(d.metrics_age_days, w.metrics_age_days)
    as metrics_age_days,
  case
    when greatest(d.metrics_age_days, w.metrics_age_days) <= 2
      then 'Fresh'
    when greatest(d.metrics_age_days, w.metrics_age_days) <= 4
      then 'Delayed'
    else 'Stale'
  end as metrics_status,
  case
    when least(d.post_count, w.post_count) >= 10 then 'High'
    when least(d.post_count, w.post_count) >= 6 then 'Medium'
    when least(d.post_count, w.post_count) >= 3 then 'Low'
    else 'Experimental'
  end as overall_confidence,
  (
    least(d.post_count, w.post_count) >= 3
    and greatest(d.metrics_age_days, w.metrics_age_days) <= 2
  ) as recommendation_ready_for_approval_mode
from best_day d
join best_window w using (platform);


revoke all on public.looker_posting_day_recommendations
  from public, anon, authenticated;
revoke all on public.looker_time_window_recommendations
  from public, anon, authenticated;
revoke all on public.looker_posting_recommendation_summary
  from public, anon, authenticated;

grant select on public.looker_posting_day_recommendations
  to creator_dashboard_reader;
grant select on public.looker_time_window_recommendations
  to creator_dashboard_reader;
grant select on public.looker_posting_recommendation_summary
  to creator_dashboard_reader;

commit;
