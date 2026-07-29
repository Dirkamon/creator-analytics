-- Creator Analytics
-- Content-aware shadow scheduling preview
-- File: Database/023_content_aware_shadow_schedule_preview.sql
--
-- Purpose:
--   1. Reproduce the current platform-wide scheduling assignment in read-only form.
--   2. Select the most specific eligible content-aware recommendation for each
--      queued Buffer post, including safe fallback to Platform Overall.
--   3. Place repeated recommendations on successive weekly occurrences.
--   4. Flag daily-limit and minimum-gap conflicts before any live integration.
--
-- Safety:
--   - Does not insert or update schedule_change_proposals.
--   - Does not modify refresh_schedule_proposals().
--   - Does not call Buffer or Make.
--   - Safe to rerun.
--
-- Preview horizon:
--   - Starts two local calendar days from today, matching the Make scenario.
--   - Covers 21 days.
--
-- Exact content-aware time:
--   - Uses the midpoint of the selected four-hour recommendation window:
--     2 AM, 6 AM, 10 AM, 2 PM, 6 PM, or 10 PM.

begin;

create or replace view public.looker_content_aware_shadow_schedule as
with active_settings as (
  select
    platform,
    content_format,
    max_posts_per_day,
    min_gap_hours,
    protected_hours,
    timezone_name
  from public.scheduling_cadence_settings
  where is_active = true
    and posts_per_week > 0
    and content_format = 'short_form'
),

scheduled_posts as (
  select
    d.buffer_post_id,
    d.platform,
    'short_form'::text as content_format,
    d.post_text,
    d.external_link,

    d.published_at_utc as current_buffer_due_at_utc,
    d.published_at_local as current_buffer_due_at_local,

    d.clip_group,
    d.game,
    d.content_type,
    d.vibe,
    coalesce(d.hook_type, '(no hook)') as hook_type,

    (
      d.game is not null
      and d.content_type is not null
      and d.vibe is not null
    ) as labels_complete,

    s.max_posts_per_day,
    s.min_gap_hours,
    s.protected_hours,
    s.timezone_name,

    row_number() over (
      partition by d.platform
      order by
        d.published_at_utc asc,
        d.buffer_post_id asc
    )::integer as post_sequence

  from public.looker_dashboard_posts d
  join active_settings s
    on s.platform = d.platform

  where d.status = 'scheduled'
    and d.published_at_utc is not null
    and d.published_at_utc >
      now() + make_interval(hours => s.protected_hours)
),

calendar_dates as (
  select
    s.platform,
    s.content_format,
    s.timezone_name,
    s.protected_hours,
    gs.local_timestamp::date as local_date
  from active_settings s
  cross join lateral generate_series(
    (
      (now() at time zone s.timezone_name)::date + 2
    )::timestamp,
    (
      (now() at time zone s.timezone_name)::date + 23
    )::timestamp,
    interval '1 day'
  ) as gs(local_timestamp)
),

platform_future_slots as (
  select
    w.platform,
    w.content_format,
    w.slot_rank,
    w.source_recommendation_rank,
    w.publish_iso_day,
    w.publish_day_name,
    w.scheduled_hour_local,
    w.scheduled_time_local,
    w.recommended_window,
    w.recommendation_score,
    w.confidence,
    w.supporting_sample_size,
    w.metrics_status,
    w.timezone_name,

    c.local_date + w.scheduled_time_local
      as platform_plan_proposed_at_local,

    (
      c.local_date + w.scheduled_time_local
    ) at time zone w.timezone_name
      as platform_plan_proposed_at_utc,

    row_number() over (
      partition by w.platform
      order by
        c.local_date asc,
        w.scheduled_time_local asc,
        w.slot_rank asc
    )::integer as slot_sequence

  from public.looker_weekly_slot_plan w
  join calendar_dates c
    on c.platform = w.platform
   and c.content_format = w.content_format
   and extract(isodow from c.local_date)::integer =
       w.publish_iso_day
  join active_settings s
    on s.platform = w.platform
   and s.content_format = w.content_format

  where (
    c.local_date + w.scheduled_time_local
  ) at time zone w.timezone_name >
    now() + make_interval(hours => s.protected_hours)
),

platform_plan_pairing as (
  select
    p.buffer_post_id,

    f.slot_rank as platform_plan_slot_rank,
    f.source_recommendation_rank
      as platform_plan_source_recommendation_rank,
    f.publish_iso_day as platform_plan_publish_iso_day,
    f.publish_day_name as platform_plan_publish_day_name,
    f.scheduled_hour_local as platform_plan_hour_local,
    f.recommended_window as platform_plan_window,
    f.recommendation_score as platform_plan_score,
    f.confidence as platform_plan_confidence,
    f.supporting_sample_size
      as platform_plan_supporting_sample_size,
    f.metrics_status as platform_plan_metrics_status,
    f.platform_plan_proposed_at_local,
    f.platform_plan_proposed_at_utc

  from scheduled_posts p
  left join platform_future_slots f
    on f.platform = p.platform
   and f.slot_sequence = p.post_sequence
),

content_candidates as (
  select
    p.buffer_post_id,
    p.platform,

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

  from scheduled_posts p
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
    p.buffer_post_id,
    p.platform,

    'Platform Overall'::text as model_level,
    5::integer as model_priority,
    p.platform::text as content_group,
    0::integer as minimum_sample_size,
    o.platform_post_count::integer as group_sample_size,

    o.publish_iso_day::integer as publish_iso_day,
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

  from scheduled_posts p
  join public.looker_joint_posting_recommendations o
    on o.platform = p.platform
   and o.recommendation_rank = 1
),

all_recommendation_candidates as (
  select * from content_candidates
  union all
  select * from overall_candidates
),

chosen_recommendations as (
  select
    c.*,

    row_number() over (
      partition by c.buffer_post_id
      order by c.model_priority
    )::integer as fallback_choice_rank

  from all_recommendation_candidates c
),

selected_recommendations as (
  select
    c.buffer_post_id,
    c.platform,

    c.model_level as selected_model_level,
    c.model_priority as selected_model_priority,
    c.content_group as selected_content_group,
    c.minimum_sample_size,
    c.group_sample_size,

    c.publish_iso_day as content_publish_iso_day,
    c.publish_day_name as content_publish_day_name,
    c.window_start_hour as content_window_start_hour,
    c.window_end_hour as content_window_end_hour,
    c.time_window as content_recommended_window,
    c.recommended_slot as content_recommended_slot,

    least(
      c.window_start_hour + 2,
      c.window_end_hour
    )::integer as content_target_hour_local,

    c.recommendation_score
      as content_recommendation_score,
    c.confidence as content_confidence,
    c.metrics_status as content_metrics_status,
    c.recommendation_ready_for_preview,

    case c.model_priority
      when 1 then
        'Full label combination met the 12-post threshold'
      when 2 then
        'Hook-level group was too small; used Game + Content Type + Vibe'
      when 3 then
        'More specific groups were too small; used Game + Content Type'
      when 4 then
        'More specific groups were too small; used Game'
      else
        'No content-specific group met its threshold; used Platform Overall'
    end::text as fallback_reason

  from chosen_recommendations c
  where c.fallback_choice_rank = 1
),

target_ordered as (
  select
    p.buffer_post_id,
    p.platform,
    p.post_sequence,
    p.timezone_name,
    p.protected_hours,

    r.selected_model_level,
    r.selected_model_priority,
    r.selected_content_group,
    r.minimum_sample_size,
    r.group_sample_size,

    r.content_publish_iso_day,
    r.content_publish_day_name,
    r.content_window_start_hour,
    r.content_window_end_hour,
    r.content_recommended_window,
    r.content_recommended_slot,
    r.content_target_hour_local,

    r.content_recommendation_score,
    r.content_confidence,
    r.content_metrics_status,
    r.recommendation_ready_for_preview,
    r.fallback_reason,

    row_number() over (
      partition by
        p.platform,
        r.content_publish_iso_day,
        r.content_target_hour_local
      order by
        p.post_sequence,
        p.buffer_post_id
    )::integer as target_occurrence_sequence

  from scheduled_posts p
  join selected_recommendations r
    on r.buffer_post_id = p.buffer_post_id
),

target_keys as (
  select distinct
    platform,
    content_publish_iso_day,
    content_target_hour_local,
    timezone_name,
    protected_hours
  from target_ordered
  where content_publish_iso_day is not null
    and content_target_hour_local is not null
),

target_occurrences as (
  select
    k.platform,
    k.content_publish_iso_day,
    k.content_target_hour_local,
    k.timezone_name,

    c.local_date
      + make_time(k.content_target_hour_local, 0, 0)
      as content_aware_proposed_at_local,

    (
      c.local_date
      + make_time(k.content_target_hour_local, 0, 0)
    ) at time zone k.timezone_name
      as content_aware_proposed_at_utc,

    row_number() over (
      partition by
        k.platform,
        k.content_publish_iso_day,
        k.content_target_hour_local
      order by c.local_date
    )::integer as occurrence_sequence

  from target_keys k
  join calendar_dates c
    on c.platform = k.platform
   and extract(isodow from c.local_date)::integer =
       k.content_publish_iso_day

  where (
    c.local_date
    + make_time(k.content_target_hour_local, 0, 0)
  ) at time zone k.timezone_name >
    now() + make_interval(hours => k.protected_hours)
),

content_shadow_pairing as (
  select
    t.buffer_post_id,

    t.selected_model_level,
    t.selected_model_priority,
    t.selected_content_group,
    t.minimum_sample_size,
    t.group_sample_size,

    t.content_publish_iso_day,
    t.content_publish_day_name,
    t.content_window_start_hour,
    t.content_window_end_hour,
    t.content_recommended_window,
    t.content_recommended_slot,
    t.content_target_hour_local,

    t.content_recommendation_score,
    t.content_confidence,
    t.content_metrics_status,
    t.recommendation_ready_for_preview,
    t.fallback_reason,

    o.content_aware_proposed_at_local,
    o.content_aware_proposed_at_utc

  from target_ordered t
  left join target_occurrences o
    on o.platform = t.platform
   and o.content_publish_iso_day =
       t.content_publish_iso_day
   and o.content_target_hour_local =
       t.content_target_hour_local
   and o.occurrence_sequence =
       t.target_occurrence_sequence
),

combined as (
  select
    p.buffer_post_id,
    p.platform,
    p.content_format,
    p.post_sequence,

    p.post_text,
    p.external_link,
    p.current_buffer_due_at_local,
    p.current_buffer_due_at_utc,

    p.clip_group,
    p.game,
    p.content_type,
    p.vibe,
    p.hook_type,
    p.labels_complete,

    p.max_posts_per_day,
    p.min_gap_hours,
    p.protected_hours,
    p.timezone_name,

    pp.platform_plan_slot_rank,
    pp.platform_plan_source_recommendation_rank,
    pp.platform_plan_publish_iso_day,
    pp.platform_plan_publish_day_name,
    pp.platform_plan_hour_local,
    pp.platform_plan_window,
    pp.platform_plan_score,
    pp.platform_plan_confidence,
    pp.platform_plan_supporting_sample_size,
    pp.platform_plan_metrics_status,
    pp.platform_plan_proposed_at_local,
    pp.platform_plan_proposed_at_utc,

    cs.selected_model_level,
    cs.selected_model_priority,
    cs.selected_content_group,
    cs.minimum_sample_size,
    cs.group_sample_size,

    cs.content_publish_iso_day,
    cs.content_publish_day_name,
    cs.content_window_start_hour,
    cs.content_window_end_hour,
    cs.content_recommended_window,
    cs.content_recommended_slot,
    cs.content_target_hour_local,

    cs.content_recommendation_score,
    cs.content_confidence,
    cs.content_metrics_status,
    cs.recommendation_ready_for_preview,
    cs.fallback_reason,

    cs.content_aware_proposed_at_local,
    cs.content_aware_proposed_at_utc

  from scheduled_posts p
  left join platform_plan_pairing pp
    on pp.buffer_post_id = p.buffer_post_id
  left join content_shadow_pairing cs
    on cs.buffer_post_id = p.buffer_post_id
),

guardrail_inputs as (
  select
    c.*,

    count(*) filter (
      where c.content_aware_proposed_at_local is not null
    ) over (
      partition by
        c.platform,
        c.content_aware_proposed_at_local::date
    )::integer as content_posts_that_day,

    lag(c.content_aware_proposed_at_utc) over (
      partition by c.platform
      order by
        c.content_aware_proposed_at_utc nulls last,
        c.buffer_post_id
    ) as previous_content_proposed_at_utc

  from combined c
),

finalized as (
  select
    g.*,

    (
      extract(
        epoch from (
          g.content_aware_proposed_at_utc
          - g.previous_content_proposed_at_utc
        )
      ) / 3600.0
    ) as content_gap_hours_raw

  from guardrail_inputs g
)

select
  buffer_post_id,
  platform,
  content_format,
  post_sequence,

  post_text,
  external_link,
  current_buffer_due_at_local,
  current_buffer_due_at_utc,

  clip_group,
  game,
  content_type,
  vibe,
  hook_type,
  labels_complete,

  platform_plan_slot_rank,
  platform_plan_source_recommendation_rank,
  platform_plan_publish_iso_day,
  platform_plan_publish_day_name,
  platform_plan_hour_local,
  platform_plan_window,
  platform_plan_score,
  platform_plan_confidence,
  platform_plan_supporting_sample_size,
  platform_plan_metrics_status,
  platform_plan_proposed_at_local,
  platform_plan_proposed_at_utc,

  selected_model_level,
  selected_model_priority,
  selected_content_group,
  group_sample_size,
  minimum_sample_size,
  content_publish_iso_day,
  content_publish_day_name,
  content_target_hour_local,
  content_recommended_window,
  content_recommended_slot,
  content_recommendation_score,
  content_confidence,
  content_metrics_status,
  recommendation_ready_for_preview,
  fallback_reason,
  content_aware_proposed_at_local,
  content_aware_proposed_at_utc,

  content_posts_that_day,
  round(content_gap_hours_raw::numeric, 1)
    as content_gap_hours,

  case
    when content_aware_proposed_at_local is null then
      'No content-aware occurrence inside the 21-day horizon'
    when content_posts_that_day > max_posts_per_day then
      'Review: maximum posts per day would be exceeded'
    when content_gap_hours_raw is not null
         and content_gap_hours_raw < min_gap_hours then
      'Review: minimum same-platform gap would be violated'
    else
      'Pass'
  end::text as content_guardrail_status,

  case
    when selected_model_level = 'Platform Overall' then
      'Platform Overall fallback'
    when platform_plan_proposed_at_local is null then
      'No current platform-plan comparison'
    when platform_plan_publish_iso_day =
         content_publish_iso_day
         and platform_plan_window =
             content_recommended_window then
      'Same recommendation window'
    else
      'Content-aware recommendation differs'
  end::text as recommendation_comparison,

  (
    platform_plan_proposed_at_local
    is not distinct from
    content_aware_proposed_at_local
  ) as exact_schedule_matches,

  round(
    (
      extract(
        epoch from (
          content_aware_proposed_at_utc
          - platform_plan_proposed_at_utc
        )
      ) / 3600.0
    )::numeric,
    1
  ) as schedule_shift_hours,

  (
    labels_complete
    and recommendation_ready_for_preview
    and content_aware_proposed_at_local is not null
    and content_posts_that_day <= max_posts_per_day
    and (
      content_gap_hours_raw is null
      or content_gap_hours_raw >= min_gap_hours
    )
  ) as shadow_ready_for_live_test,

  timezone_name

from finalized;


create or replace view public.looker_content_aware_shadow_schedule_summary as
select
  platform,

  count(*)::integer as queued_posts,
  count(*) filter (
    where labels_complete
  )::integer as labeled_posts,

  count(*) filter (
    where selected_model_level <> 'Platform Overall'
  )::integer as content_specific_posts,

  count(*) filter (
    where selected_model_level = 'Platform Overall'
  )::integer as platform_fallback_posts,

  count(*) filter (
    where recommendation_comparison =
      'Content-aware recommendation differs'
  )::integer as recommendation_changes,

  count(*) filter (
    where content_guardrail_status = 'Pass'
  )::integer as guardrail_passes,

  count(*) filter (
    where shadow_ready_for_live_test
  )::integer as ready_for_live_test,

  min(content_aware_proposed_at_local)
    as first_content_aware_slot_local,

  max(content_aware_proposed_at_local)
    as last_content_aware_slot_local

from public.looker_content_aware_shadow_schedule
group by platform;


comment on view public.looker_content_aware_shadow_schedule is
  'Read-only comparison of the current platform-wide scheduler assignment and a content-aware shadow assignment for future queued posts.';

comment on view public.looker_content_aware_shadow_schedule_summary is
  'Platform-level counts and safety checks for the content-aware shadow schedule.';

revoke all on public.looker_content_aware_shadow_schedule
  from public, anon, authenticated;

revoke all on public.looker_content_aware_shadow_schedule_summary
  from public, anon, authenticated;

grant select on public.looker_content_aware_shadow_schedule
  to service_role;

grant select on public.looker_content_aware_shadow_schedule_summary
  to service_role;

do $$
begin
  if exists (
    select 1
    from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant select on public.looker_content_aware_shadow_schedule
      to creator_dashboard_reader;

    grant select on public.looker_content_aware_shadow_schedule_summary
      to creator_dashboard_reader;
  end if;
end;
$$;

commit;
