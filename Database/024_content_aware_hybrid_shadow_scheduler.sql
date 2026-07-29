-- Creator Analytics
-- Hybrid content-aware weekly shadow scheduler
-- File: Database/024_content_aware_hybrid_shadow_scheduler.sql
--
-- Purpose:
--   1. Keep the existing platform-wide weekly slot template and cadence.
--   2. Rank the slots inside each 14-post cadence cycle for each queued post
--      using its content-aware recommendation.
--   3. Assign every post a unique slot inside its original cadence cycle.
--   4. Prefer exact content day + window matches, then nearby slots, while
--      using the platform-wide slot score as the final ranking signal.
--   5. Expose guardrails and comparisons without changing the live scheduler.
--
-- Safety:
--   - Does not insert or update schedule_change_proposals.
--   - Does not modify refresh_schedule_proposals().
--   - Does not call Buffer or Make.
--   - Safe to rerun.
--
-- Assignment behavior:
--   - The first posts_per_week queued posts stay inside cadence cycle 1.
--   - The next posts_per_week posts stay inside cadence cycle 2, and so on.
--   - Content-specific posts are assigned before Platform Overall fallbacks
--     inside each cycle so scarce preferred slots go to the strongest model.
--   - Each weekly-template slot can be used only once per cycle.

begin;

create or replace view public.looker_content_aware_hybrid_shadow_schedule as
with recursive active_settings as (
  select
    platform,
    content_format,
    posts_per_week,
    max_posts_per_day,
    min_gap_hours,
    protected_hours,
    timezone_name
  from public.scheduling_cadence_settings
  where is_active = true
    and posts_per_week > 0
    and content_format = 'short_form'
),

queued_posts_base as (
  select
    sh.*,
    s.posts_per_week,
    s.max_posts_per_day,
    s.min_gap_hours,
    s.protected_hours,

    (
      ((sh.post_sequence - 1) / s.posts_per_week) + 1
    )::integer as cadence_cycle

  from public.looker_content_aware_shadow_schedule sh
  join active_settings s
    on s.platform = sh.platform
   and s.content_format = sh.content_format
),

ordered_posts as (
  select
    q.*,

    row_number() over (
      partition by q.platform, q.cadence_cycle
      order by
        case
          when q.selected_model_level = 'Platform Overall' then 1
          else 0
        end,
        q.selected_model_priority asc nulls last,
        q.content_recommendation_score desc nulls last,
        q.post_sequence asc,
        q.buffer_post_id asc
    )::integer as assignment_sequence

  from queued_posts_base q
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

future_slots_numbered as (
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
      as proposed_at_local,

    (
      c.local_date + w.scheduled_time_local
    ) at time zone w.timezone_name
      as proposed_at_utc,

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

future_slots as (
  select
    f.*,

    (
      ((f.slot_sequence - 1) / s.posts_per_week) + 1
    )::integer as cadence_cycle,

    (
      ((f.slot_sequence - 1) % s.posts_per_week) + 1
    )::integer as cycle_slot_position,

    (
      f.platform
      || ':'
      || to_char(
           f.proposed_at_local,
           'YYYY-MM-DD"T"HH24:MI:SS'
         )
    )::text as slot_instance_key

  from future_slots_numbered f
  join active_settings s
    on s.platform = f.platform
   and s.content_format = f.content_format
),

candidate_components as (
  select
    p.platform,
    p.buffer_post_id,
    p.cadence_cycle,
    p.assignment_sequence,

    f.slot_instance_key,
    f.slot_sequence,
    f.cycle_slot_position,
    f.slot_rank,
    f.source_recommendation_rank,
    f.publish_iso_day,
    f.publish_day_name,
    f.scheduled_hour_local,
    f.scheduled_time_local,
    f.recommended_window,
    f.recommendation_score
      as platform_slot_recommendation_score,
    f.confidence as platform_slot_confidence,
    f.supporting_sample_size
      as platform_slot_supporting_sample_size,
    f.metrics_status as platform_slot_metrics_status,
    f.proposed_at_local,
    f.proposed_at_utc,

    (
      f.publish_iso_day = p.content_publish_iso_day
    ) as content_day_matches,

    (
      f.recommended_window = p.content_recommended_window
    ) as content_window_matches,

    case
      when p.content_publish_iso_day is null then 3
      else least(
        abs(f.publish_iso_day - p.content_publish_iso_day),
        7 - abs(f.publish_iso_day - p.content_publish_iso_day)
      )
    end::integer as content_day_distance,

    case
      when p.content_target_hour_local is null then 12
      else least(
        abs(
          f.scheduled_hour_local
          - p.content_target_hour_local
        ),
        24 - abs(
          f.scheduled_hour_local
          - p.content_target_hour_local
        )
      )
    end::integer as content_hour_distance

  from ordered_posts p
  join future_slots f
    on f.platform = p.platform
   and f.content_format = p.content_format
   and f.cadence_cycle = p.cadence_cycle
),

candidate_scores as (
  select
    c.*,

    (
      case
        when c.content_day_matches
         and c.content_window_matches
          then 1000
        else 0
      end

      + case
          when c.content_day_matches then 260
          else 0
        end

      + case
          when c.content_window_matches then 220
          else 0
        end

      + greatest(
          0,
          120 - (c.content_day_distance * 30)
        )

      + greatest(
          0,
          80 - (c.content_hour_distance * 6)
        )

      + coalesce(
          c.platform_slot_recommendation_score,
          0
        )

      - (coalesce(c.slot_rank, 99) * 0.10)
      - (c.cycle_slot_position * 0.01)
    )::numeric(12,2) as hybrid_assignment_score

  from candidate_components c
),

assignments as (
  -- Seed one independent recursive assignment chain for every
  -- platform + cadence cycle.
  select
    p.platform,
    p.cadence_cycle,
    p.assignment_sequence,
    p.buffer_post_id,
    c.slot_instance_key,
    array[c.slot_instance_key]::text[] as used_slot_keys

  from ordered_posts p

  join lateral (
    select
      cs.slot_instance_key
    from candidate_scores cs
    where cs.buffer_post_id = p.buffer_post_id
    order by
      cs.hybrid_assignment_score desc,
      cs.source_recommendation_rank asc,
      cs.slot_rank asc,
      cs.slot_sequence asc
    limit 1
  ) c on true

  where p.assignment_sequence = 1

  union all

  select
    p.platform,
    p.cadence_cycle,
    p.assignment_sequence,
    p.buffer_post_id,
    c.slot_instance_key,
    array_append(
      a.used_slot_keys,
      c.slot_instance_key
    ) as used_slot_keys

  from assignments a

  join ordered_posts p
    on p.platform = a.platform
   and p.cadence_cycle = a.cadence_cycle
   and p.assignment_sequence =
       a.assignment_sequence + 1

  join lateral (
    select
      cs.slot_instance_key
    from candidate_scores cs
    where cs.buffer_post_id = p.buffer_post_id
      and not (
        cs.slot_instance_key = any(a.used_slot_keys)
      )
    order by
      cs.hybrid_assignment_score desc,
      cs.source_recommendation_rank asc,
      cs.slot_rank asc,
      cs.slot_sequence asc
    limit 1
  ) c on true
),

raw_assignments as (
  select
    p.buffer_post_id,
    p.platform,
    p.content_format,
    p.post_sequence,
    p.cadence_cycle,
    p.assignment_sequence,

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

    p.platform_plan_slot_rank,
    p.platform_plan_source_recommendation_rank,
    p.platform_plan_publish_iso_day,
    p.platform_plan_publish_day_name,
    p.platform_plan_hour_local,
    p.platform_plan_window,
    p.platform_plan_score,
    p.platform_plan_confidence,
    p.platform_plan_supporting_sample_size,
    p.platform_plan_metrics_status,
    p.platform_plan_proposed_at_local,
    p.platform_plan_proposed_at_utc,

    p.selected_model_level,
    p.selected_model_priority,
    p.selected_content_group,
    p.group_sample_size,
    p.minimum_sample_size,

    p.content_publish_iso_day,
    p.content_publish_day_name,
    p.content_target_hour_local,
    p.content_recommended_window,
    p.content_recommended_slot,
    p.content_recommendation_score,
    p.content_confidence,
    p.content_metrics_status,
    p.recommendation_ready_for_preview,
    p.fallback_reason,

    cs.slot_sequence as hybrid_slot_sequence,
    cs.cycle_slot_position
      as hybrid_cycle_slot_position,
    cs.slot_rank as hybrid_slot_rank,
    cs.source_recommendation_rank
      as hybrid_source_recommendation_rank,
    cs.publish_iso_day as hybrid_publish_iso_day,
    cs.publish_day_name as hybrid_publish_day_name,
    cs.scheduled_hour_local as hybrid_hour_local,
    cs.scheduled_time_local as hybrid_time_local,
    cs.recommended_window as hybrid_recommended_window,
    cs.platform_slot_recommendation_score,
    cs.platform_slot_confidence,
    cs.platform_slot_supporting_sample_size,
    cs.platform_slot_metrics_status,
    cs.proposed_at_local as hybrid_proposed_at_local,
    cs.proposed_at_utc as hybrid_proposed_at_utc,

    cs.content_day_matches,
    cs.content_window_matches,
    cs.content_day_distance,
    cs.content_hour_distance,
    cs.hybrid_assignment_score,

    p.posts_per_week,
    p.max_posts_per_day,
    p.min_gap_hours,
    p.protected_hours,
    p.timezone_name

  from ordered_posts p

  left join assignments a
    on a.platform = p.platform
   and a.cadence_cycle = p.cadence_cycle
   and a.assignment_sequence =
       p.assignment_sequence
   and a.buffer_post_id = p.buffer_post_id

  left join candidate_scores cs
    on cs.buffer_post_id = p.buffer_post_id
   and cs.slot_instance_key = a.slot_instance_key
),

guardrail_inputs as (
  select
    r.*,

    count(*) filter (
      where r.hybrid_proposed_at_local is not null
    ) over (
      partition by
        r.platform,
        r.hybrid_proposed_at_local::date
    )::integer as hybrid_posts_that_day,

    lag(r.hybrid_proposed_at_utc) over (
      partition by r.platform
      order by
        r.hybrid_proposed_at_utc nulls last,
        r.buffer_post_id
    ) as previous_hybrid_proposed_at_utc

  from raw_assignments r
),

finalized as (
  select
    g.*,

    (
      extract(
        epoch from (
          g.hybrid_proposed_at_utc
          - g.previous_hybrid_proposed_at_utc
        )
      ) / 3600.0
    ) as hybrid_gap_hours_raw

  from guardrail_inputs g
)

select
  buffer_post_id,
  platform,
  content_format,
  post_sequence,
  cadence_cycle,
  assignment_sequence,

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

  hybrid_slot_sequence,
  hybrid_cycle_slot_position,
  hybrid_slot_rank,
  hybrid_source_recommendation_rank,
  hybrid_publish_iso_day,
  hybrid_publish_day_name,
  hybrid_hour_local,
  hybrid_time_local,
  hybrid_recommended_window,
  platform_slot_recommendation_score,
  platform_slot_confidence,
  platform_slot_supporting_sample_size,
  platform_slot_metrics_status,
  hybrid_proposed_at_local,
  hybrid_proposed_at_utc,

  content_day_matches,
  content_window_matches,
  content_day_distance,
  content_hour_distance,
  hybrid_assignment_score,

  case
    when hybrid_proposed_at_local is null then
      'No slot available inside this cadence cycle'
    when content_day_matches
         and content_window_matches then
      'Exact content day + window'
    when content_day_matches then
      'Preferred content day; alternate window'
    when content_window_matches then
      'Preferred content window; alternate day'
    else
      'Nearby platform slot'
  end::text as content_match_class,

  hybrid_posts_that_day,

  round(
    hybrid_gap_hours_raw::numeric,
    1
  ) as hybrid_gap_hours,

  case
    when hybrid_proposed_at_local is null then
      'Review: no slot available inside cadence cycle'
    when hybrid_posts_that_day > max_posts_per_day then
      'Review: maximum posts per day would be exceeded'
    when hybrid_gap_hours_raw is not null
         and hybrid_gap_hours_raw < min_gap_hours then
      'Review: minimum same-platform gap would be violated'
    else
      'Pass'
  end::text as hybrid_guardrail_status,

  case
    when hybrid_proposed_at_local is null then
      'No hybrid assignment'
    when platform_plan_proposed_at_local
         is not distinct from
         hybrid_proposed_at_local then
      'Same exact platform-plan slot'
    when platform_plan_publish_iso_day =
         hybrid_publish_iso_day
         and platform_plan_window =
             hybrid_recommended_window then
      'Same platform-plan recommendation window'
    else
      'Reassigned inside the same cadence cycle'
  end::text as platform_plan_comparison,

  (
    platform_plan_proposed_at_local
    is not distinct from
    hybrid_proposed_at_local
  ) as exact_platform_plan_match,

  round(
    (
      extract(
        epoch from (
          hybrid_proposed_at_utc
          - platform_plan_proposed_at_utc
        )
      ) / 3600.0
    )::numeric,
    1
  ) as platform_plan_shift_hours,

  (
    hybrid_slot_sequence is not null
    and (
      ((hybrid_slot_sequence - 1) / posts_per_week) + 1
    )::integer = cadence_cycle
  ) as stayed_inside_cadence_cycle,

  (
    labels_complete
    and recommendation_ready_for_preview
    and hybrid_proposed_at_local is not null
    and hybrid_posts_that_day <= max_posts_per_day
    and (
      hybrid_gap_hours_raw is null
      or hybrid_gap_hours_raw >= min_gap_hours
    )
  ) as shadow_ready_for_live_test,

  max_posts_per_day,
  min_gap_hours,
  protected_hours,
  timezone_name

from finalized;


create or replace view
  public.looker_content_aware_hybrid_shadow_schedule_summary
as
select
  platform,

  count(*)::integer as queued_posts,

  count(*) filter (
    where hybrid_proposed_at_local is not null
  )::integer as assigned_posts,

  count(*) filter (
    where selected_model_level <> 'Platform Overall'
  )::integer as content_specific_posts,

  count(*) filter (
    where selected_model_level = 'Platform Overall'
  )::integer as platform_fallback_posts,

  count(*) filter (
    where content_match_class =
      'Exact content day + window'
  )::integer as exact_content_matches,

  count(*) filter (
    where platform_plan_comparison =
      'Reassigned inside the same cadence cycle'
  )::integer as platform_plan_reassignments,

  count(*) filter (
    where hybrid_guardrail_status = 'Pass'
  )::integer as guardrail_passes,

  count(*) filter (
    where stayed_inside_cadence_cycle
  )::integer as cadence_cycle_passes,

  count(*) filter (
    where shadow_ready_for_live_test
  )::integer as ready_for_live_test,

  max(cadence_cycle)::integer as cadence_cycles_used,

  min(hybrid_proposed_at_local)
    as first_hybrid_slot_local,

  max(hybrid_proposed_at_local)
    as last_hybrid_slot_local

from public.looker_content_aware_hybrid_shadow_schedule
group by platform;


comment on view
  public.looker_content_aware_hybrid_shadow_schedule
is
  'Read-only hybrid scheduler that assigns queued posts to unique existing weekly-template slots, ranked by content-aware preference, without leaving their cadence cycle.';

comment on view
  public.looker_content_aware_hybrid_shadow_schedule_summary
is
  'Platform-level assignment, cadence, guardrail, and readiness totals for the hybrid content-aware shadow scheduler.';

revoke all on
  public.looker_content_aware_hybrid_shadow_schedule
from public, anon, authenticated;

revoke all on
  public.looker_content_aware_hybrid_shadow_schedule_summary
from public, anon, authenticated;

grant select on
  public.looker_content_aware_hybrid_shadow_schedule
to service_role;

grant select on
  public.looker_content_aware_hybrid_shadow_schedule_summary
to service_role;

do $$
begin
  if exists (
    select 1
    from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant select on
      public.looker_content_aware_hybrid_shadow_schedule
    to creator_dashboard_reader;

    grant select on
      public.looker_content_aware_hybrid_shadow_schedule_summary
    to creator_dashboard_reader;
  end if;
end;
$$;

commit;
