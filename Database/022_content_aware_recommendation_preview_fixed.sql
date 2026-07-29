-- Creator Analytics
-- Read-only content-aware posting recommendations
-- File: Database/022_content_aware_recommendation_preview.sql
--
-- Purpose:
--   1. Score posting day + 4-hour time windows separately for content groups.
--   2. Use the same 65% views / 20% interaction / 15% sample-size scoring
--      and the same 8-post shrinkage weight as the current joint model.
--   3. Expose hierarchical eligibility thresholds without changing Buffer,
--      Make, the weekly slot plan, or refresh_schedule_proposals().
--   4. Preview the fallback level that each labeled content profile would use.
--
-- Eligibility thresholds:
--   Game + Content Type + Vibe + Hook : 12 posts
--   Game + Content Type + Vibe        : 10 posts
--   Game + Content Type               :  8 posts
--   Game                              :  8 posts
--   Platform Overall                  : always available fallback

begin;

create or replace view public.looker_content_aware_recommendations as
with base as (
  select
    d.platform,
    d.game,
    d.content_type,
    d.vibe,
    coalesce(d.hook_type, '(no hook)') as hook_type,
    d.publish_iso_day,
    d.publish_day_name,
    d.publish_hour,

    case
      when d.publish_hour between 0 and 3 then 0
      when d.publish_hour between 4 and 7 then 4
      when d.publish_hour between 8 and 11 then 8
      when d.publish_hour between 12 and 15 then 12
      when d.publish_hour between 16 and 19 then 16
      when d.publish_hour between 20 and 23 then 20
      else null
    end as window_start_hour,

    case
      when d.publish_hour between 0 and 3 then 3
      when d.publish_hour between 4 and 7 then 7
      when d.publish_hour between 8 and 11 then 11
      when d.publish_hour between 12 and 15 then 15
      when d.publish_hour between 16 and 19 then 19
      when d.publish_hour between 20 and 23 then 23
      else null
    end as window_end_hour,

    case
      when d.publish_hour between 0 and 3 then '12 AM–3:59 AM'
      when d.publish_hour between 4 and 7 then '4 AM–7:59 AM'
      when d.publish_hour between 8 and 11 then '8 AM–11:59 AM'
      when d.publish_hour between 12 and 15 then '12 PM–3:59 PM'
      when d.publish_hour between 16 and 19 then '4 PM–7:59 PM'
      when d.publish_hour between 20 and 23 then '8 PM–11:59 PM'
      else null
    end::text as time_window,

    d.views::numeric as views,
    coalesce(d.calculated_interaction_rate, 0::numeric)
      as calculated_interaction_rate,
    d.latest_metric_date

  from public.looker_dashboard_posts d
  where d.status = 'sent'
    and d.published_at_local is not null
    and d.publish_iso_day is not null
    and d.publish_day_name is not null
    and d.publish_hour is not null
    and d.views is not null
    and d.views > 0
    and d.game is not null
    and d.content_type is not null
    and d.vibe is not null
),

platform_baseline as (
  select
    platform,
    count(*)::integer as platform_post_count,
    avg(views) as platform_avg_views,
    avg(calculated_interaction_rate) as platform_avg_interaction_rate,
    max(latest_metric_date) as platform_latest_metric_date
  from base
  group by platform
),

expanded as (
  select
    b.platform,
    m.model_level,
    m.model_priority,
    m.minimum_sample_size,
    m.game,
    m.content_type,
    m.vibe,
    m.hook_type,
    m.content_group,
    b.publish_iso_day,
    b.publish_day_name,
    b.window_start_hour,
    b.window_end_hour,
    b.time_window,
    b.views,
    b.calculated_interaction_rate,
    b.latest_metric_date
  from base b
  cross join lateral (
    values
      (
        'Game + Content Type + Vibe + Hook'::text,
        1::integer,
        12::integer,
        b.game,
        b.content_type,
        b.vibe,
        b.hook_type,
        b.game || ' | ' || b.content_type || ' | ' || b.vibe || ' | ' || b.hook_type
      ),
      (
        'Game + Content Type + Vibe'::text,
        2::integer,
        10::integer,
        b.game,
        b.content_type,
        b.vibe,
        null::text,
        b.game || ' | ' || b.content_type || ' | ' || b.vibe
      ),
      (
        'Game + Content Type'::text,
        3::integer,
        8::integer,
        b.game,
        b.content_type,
        null::text,
        null::text,
        b.game || ' | ' || b.content_type
      ),
      (
        'Game'::text,
        4::integer,
        8::integer,
        b.game,
        null::text,
        null::text,
        null::text,
        b.game
      )
  ) as m(
    model_level,
    model_priority,
    minimum_sample_size,
    game,
    content_type,
    vibe,
    hook_type,
    content_group
  )
),

group_baseline as (
  select
    platform,
    model_level,
    model_priority,
    minimum_sample_size,
    game,
    content_type,
    vibe,
    hook_type,
    content_group,
    count(*)::integer as group_sample_size,
    avg(views) as group_avg_views,
    avg(calculated_interaction_rate) as group_avg_interaction_rate,
    max(latest_metric_date) as group_latest_metric_date
  from expanded
  group by
    platform,
    model_level,
    model_priority,
    minimum_sample_size,
    game,
    content_type,
    vibe,
    hook_type,
    content_group
),

slot_grouped as (
  select
    platform,
    model_level,
    model_priority,
    minimum_sample_size,
    game,
    content_type,
    vibe,
    hook_type,
    content_group,
    publish_iso_day,
    publish_day_name,
    window_start_hour,
    window_end_hour,
    time_window,
    count(*)::integer as slot_post_count,
    avg(views) as avg_views,
    percentile_cont(0.5::double precision)
      within group (order by views::double precision)::numeric
      as median_views,
    avg(calculated_interaction_rate) as avg_interaction_rate,
    max(latest_metric_date) as latest_metric_date
  from expanded
  group by
    platform,
    model_level,
    model_priority,
    minimum_sample_size,
    game,
    content_type,
    vibe,
    hook_type,
    content_group,
    publish_iso_day,
    publish_day_name,
    window_start_hour,
    window_end_hour,
    time_window
),

adjusted as (
  select
    s.*,
    g.group_sample_size,
    g.group_avg_views,
    g.group_avg_interaction_rate,
    p.platform_post_count,
    p.platform_avg_views,
    p.platform_avg_interaction_rate,

    (
      s.slot_post_count::numeric * s.avg_views
      + 8::numeric * p.platform_avg_views
    ) / (s.slot_post_count + 8)::numeric
      as adjusted_avg_views,

    (
      s.slot_post_count::numeric * s.avg_interaction_rate
      + 8::numeric * p.platform_avg_interaction_rate
    ) / (s.slot_post_count + 8)::numeric
      as adjusted_interaction_rate,

    current_date - p.platform_latest_metric_date as metrics_age_days

  from slot_grouped s
  join group_baseline g
    on g.platform = s.platform
   and g.model_priority = s.model_priority
   and g.content_group = s.content_group
  join platform_baseline p
    on p.platform = s.platform
),

scored as (
  select
    a.*,
    (
      (
        0.65::double precision
        * percent_rank() over (
            partition by a.platform, a.model_priority, a.content_group
            order by a.adjusted_avg_views
          )
        + 0.20::double precision
        * percent_rank() over (
            partition by a.platform, a.model_priority, a.content_group
            order by a.adjusted_interaction_rate
          )
        + 0.15::double precision
        * percent_rank() over (
            partition by a.platform, a.model_priority, a.content_group
            order by a.slot_post_count
          )
      ) * 100::double precision
    )::numeric(6,1) as recommendation_score
  from adjusted a
),

ranked as (
  select
    s.*,
    row_number() over (
      partition by s.platform, s.model_priority, s.content_group
      order by
        s.recommendation_score desc,
        s.slot_post_count desc,
        s.publish_iso_day,
        s.window_start_hour
    )::integer as recommendation_rank
  from scored s
)

select
  platform,
  model_level,
  model_priority,
  content_group,
  game,
  content_type,
  vibe,
  hook_type,
  minimum_sample_size,
  group_sample_size,
  group_sample_size >= minimum_sample_size as model_eligible,
  recommendation_rank,
  publish_iso_day,
  publish_day_name,
  window_start_hour,
  window_end_hour,
  time_window,
  publish_day_name || ' · ' || time_window as recommended_slot,
  slot_post_count,
  platform_post_count,
  round(avg_views, 1) as avg_views,
  round(median_views, 1) as median_views,
  round(avg_interaction_rate, 2) as avg_interaction_rate,
  round(adjusted_avg_views, 1) as adjusted_avg_views,
  round(adjusted_interaction_rate, 2) as adjusted_interaction_rate,
  recommendation_score,

  case
    when slot_post_count >= 12 then 'High'
    when slot_post_count >= 7 then 'Medium'
    when slot_post_count >= 4 then 'Low'
    else 'Experimental'
  end::text as confidence,

  latest_metric_date,
  metrics_age_days,

  case
    when metrics_age_days <= 2 then 'Fresh'
    when metrics_age_days <= 4 then 'Delayed'
    else 'Stale'
  end::text as metrics_status,

  (
    group_sample_size >= minimum_sample_size
    and metrics_age_days <= 2
  ) as recommendation_ready_for_preview

from ranked;


create or replace view public.looker_content_aware_recommendation_summary as
select
  platform,
  model_level,
  model_priority,
  content_group,
  game,
  content_type,
  vibe,
  hook_type,
  minimum_sample_size,
  group_sample_size,
  model_eligible,
  publish_iso_day,
  publish_day_name,
  window_start_hour,
  window_end_hour,
  time_window,
  recommended_slot,
  slot_post_count,
  platform_post_count,
  avg_views,
  median_views,
  avg_interaction_rate,
  adjusted_avg_views,
  adjusted_interaction_rate,
  recommendation_score,
  confidence,
  latest_metric_date,
  metrics_age_days,
  metrics_status,
  recommendation_ready_for_preview
from public.looker_content_aware_recommendations
where recommendation_rank = 1;


create or replace view public.looker_content_aware_fallback_preview as
with profiles as (
  select distinct
    platform,
    game,
    content_type,
    vibe,
    coalesce(hook_type, '(no hook)') as hook_type
  from public.looker_dashboard_posts
  where status = 'sent'
    and views is not null
    and views > 0
    and game is not null
    and content_type is not null
    and vibe is not null
),

content_candidates as (
  select
    p.platform,
    p.game,
    p.content_type,
    p.vibe,
    p.hook_type,
    s.model_level,
    s.model_priority,
    s.content_group,
    s.minimum_sample_size,
    s.group_sample_size,
    s.publish_iso_day,
    s.publish_day_name,
    s.window_start_hour,
    s.window_end_hour,
    s.time_window,
    s.recommended_slot,
    s.recommendation_score,
    s.confidence,
    s.metrics_status,
    s.recommendation_ready_for_preview
  from profiles p
  join public.looker_content_aware_recommendation_summary s
    on s.platform = p.platform
   and s.model_eligible = true
   and (
        (
          s.model_priority = 1
          and s.game = p.game
          and s.content_type = p.content_type
          and s.vibe = p.vibe
          and s.hook_type = p.hook_type
        )
        or
        (
          s.model_priority = 2
          and s.game = p.game
          and s.content_type = p.content_type
          and s.vibe = p.vibe
        )
        or
        (
          s.model_priority = 3
          and s.game = p.game
          and s.content_type = p.content_type
        )
        or
        (
          s.model_priority = 4
          and s.game = p.game
        )
      )
),

overall_candidates as (
  select
    p.platform,
    p.game,
    p.content_type,
    p.vibe,
    p.hook_type,
    'Platform Overall'::text as model_level,
    5::integer as model_priority,
    p.platform::text as content_group,
    0::integer as minimum_sample_size,
    o.platform_post_count::integer as group_sample_size,
    o.publish_iso_day,
    o.publish_day_name,
    o.window_start_hour,
    o.window_end_hour,
    o.time_window,
    o.recommended_slot,
    o.recommendation_score,
    o.confidence,
    o.metrics_status,
    o.recommendation_ready_for_approval_mode
      as recommendation_ready_for_preview
  from profiles p
  join public.looker_joint_posting_recommendations o
    on o.platform = p.platform
   and o.recommendation_rank = 1
),

all_candidates as (
  select * from content_candidates
  union all
  select * from overall_candidates
),

chosen as (
  select
    c.*,
    row_number() over (
      partition by
        c.platform,
        c.game,
        c.content_type,
        c.vibe,
        c.hook_type
      order by c.model_priority
    )::integer as fallback_choice_rank
  from all_candidates c
)

select
  platform,
  game,
  content_type,
  vibe,
  hook_type,
  model_level as selected_model_level,
  model_priority as selected_model_priority,
  content_group as selected_content_group,
  group_sample_size,
  minimum_sample_size,
  publish_iso_day,
  publish_day_name,
  window_start_hour,
  window_end_hour,
  time_window,
  recommended_slot,
  recommendation_score,
  confidence,
  metrics_status,
  recommendation_ready_for_preview,

  case model_priority
    when 1 then 'Full label combination met the 12-post threshold'
    when 2 then 'Hook-level group was too small; used Game + Content Type + Vibe'
    when 3 then 'More specific groups were too small; used Game + Content Type'
    when 4 then 'More specific groups were too small; used Game'
    else 'No content-specific group met its threshold; used Platform Overall'
  end::text as fallback_reason

from chosen
where fallback_choice_rank = 1;


comment on view public.looker_content_aware_recommendations is
  'Read-only day and four-hour-window recommendations for hierarchical content-label groups.';

comment on view public.looker_content_aware_recommendation_summary is
  'Top-ranked posting slot for every content-aware model group.';

comment on view public.looker_content_aware_fallback_preview is
  'Read-only preview of the most specific eligible recommendation level for each observed content profile.';

revoke all on public.looker_content_aware_recommendations
  from public, anon, authenticated;
revoke all on public.looker_content_aware_recommendation_summary
  from public, anon, authenticated;
revoke all on public.looker_content_aware_fallback_preview
  from public, anon, authenticated;

grant select on public.looker_content_aware_recommendations
  to service_role;
grant select on public.looker_content_aware_recommendation_summary
  to service_role;
grant select on public.looker_content_aware_fallback_preview
  to service_role;

do $$
begin
  if exists (
    select 1
    from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant select on public.looker_content_aware_recommendations
      to creator_dashboard_reader;
    grant select on public.looker_content_aware_recommendation_summary
      to creator_dashboard_reader;
    grant select on public.looker_content_aware_fallback_preview
      to creator_dashboard_reader;
  end if;
end;
$$;

commit;
