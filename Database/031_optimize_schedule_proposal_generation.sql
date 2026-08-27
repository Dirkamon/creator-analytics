-- Creator Analytics
-- Optimize schedule proposal generation without changing scheduling behavior
-- File: Database/031_optimize_schedule_proposal_generation.sql
--
-- Adds two plan-supported indexes and one service-only single-scan reservation
-- calculation. Only the hybrid and proposal-preview definitions are replaced.
-- Their columns, types, order, ownership, ACLs, and behavior must remain exact.

begin;

create temporary table migration_031_replaced_view_contract
on commit drop
as
select
  relation.oid as relation_oid,
  relation.relname,
  relation.relowner,
  relation.relacl,
  relation.reloptions,
  (
    select array_agg(
      format(
        '%s:%s',
        attribute.attname,
        pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)
      )
      order by attribute.attnum
    )
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid = relation.oid
      and attribute.attnum > 0
      and not attribute.attisdropped
  ) as column_contract
from pg_catalog.pg_class relation
join pg_catalog.pg_namespace namespace
  on namespace.oid = relation.relnamespace
where namespace.nspname = 'public'
  and relation.relname in (
    'looker_content_aware_hybrid_shadow_schedule',
    'looker_content_aware_proposal_preview'
  )
  and relation.relkind = 'v';

do $migration$
begin
  if (select count(*) from migration_031_replaced_view_contract) <> 2 then
    raise exception
      'Migration 031 requires both migration-029 scheduling views';
  end if;
end;
$migration$;

create index if not exists
  schedule_change_proposals_buffer_post_id_idx
on public.schedule_change_proposals (buffer_post_id);

create index if not exists
  posts_scheduled_channel_due_at_idx
on public.posts (buffer_channel_id, due_at)
where status = 'scheduled'
  and due_at is not null;

create or replace function public.calculate_schedule_reservation_state(
  p_candidate_post_id text,
  p_buffer_channel_id text,
  p_proposed_due_at_utc timestamptz,
  p_min_gap_hours integer,
  p_timezone_name text,
  p_exclude_proposal_id uuid
)
returns table (
  reservation_conflict_count integer,
  fixed_daily_reservation_count integer,
  fixed_weekly_reservation_count integer
)
language plpgsql
stable
security definer
set search_path = ''
rows 1
as $function$
declare
  v_core_inputs_valid boolean;
  v_timezone_valid boolean;
begin
  v_core_inputs_valid :=
    nullif(pg_catalog.btrim(p_candidate_post_id), '') is not null
    and nullif(pg_catalog.btrim(p_buffer_channel_id), '') is not null
    and p_proposed_due_at_utc is not null
    and p_min_gap_hours is not null
    and p_min_gap_hours > 0;

  v_timezone_valid :=
    nullif(pg_catalog.btrim(p_timezone_name), '') is not null
    and exists (
      select 1
      from pg_catalog.pg_timezone_names timezone_record
      where timezone_record.name = p_timezone_name
    );

  if not v_core_inputs_valid then
    return query
    select null::integer, null::integer, null::integer;
    return;
  end if;

  return query
  with eligible_reservations as materialized (
    select
      reservation.reservation_post_id,
      reservation.reserved_at_utc,
      (
        reservation.reserved_at_utc >
          p_proposed_due_at_utc
          - pg_catalog.make_interval(hours => p_min_gap_hours)
        and reservation.reserved_at_utc <
          p_proposed_due_at_utc
          + pg_catalog.make_interval(hours => p_min_gap_hours)
      ) as is_conflict
    from public.schedule_slot_reservations reservation
    where reservation.buffer_channel_id = p_buffer_channel_id
      and reservation.reservation_post_id <> p_candidate_post_id
      and (
        p_exclude_proposal_id is null
        or reservation.reservation_proposal_id
             is distinct from p_exclude_proposal_id
      )
  ),
  conflict_total as (
    select
      count(*) filter (
        where reservation.is_conflict
      )::integer as reservation_conflict_count
    from eligible_reservations reservation
  ),
  distinct_fixed_reservations as (
    select distinct
      reservation.reservation_post_id,
      reservation.reserved_at_utc
    from eligible_reservations reservation
  ),
  target_period as (
    select
      (
        p_proposed_due_at_utc at time zone
          case when v_timezone_valid then p_timezone_name else 'UTC' end
      )::date as target_local_date,
      date_trunc(
        'week',
        p_proposed_due_at_utc at time zone
          case when v_timezone_valid then p_timezone_name else 'UTC' end
      ) as target_local_week
  ),
  capacity_total as (
    select
      count(*) filter (
        where (
          fixed.reserved_at_utc at time zone
            case when v_timezone_valid then p_timezone_name else 'UTC' end
        )::date = period.target_local_date
      )::integer as fixed_daily_reservation_count,
      count(*) filter (
        where date_trunc(
          'week',
          fixed.reserved_at_utc at time zone
            case when v_timezone_valid then p_timezone_name else 'UTC' end
        ) = period.target_local_week
      )::integer as fixed_weekly_reservation_count
    from distinct_fixed_reservations fixed
    cross join target_period period
  )
  select
    conflict.reservation_conflict_count,
    case
      when v_timezone_valid
        then capacity.fixed_daily_reservation_count
      else null::integer
    end,
    case
      when v_timezone_valid
        then capacity.fixed_weekly_reservation_count
      else null::integer
    end
  from conflict_total conflict
  cross join capacity_total capacity;
end;
$function$;

comment on function public.calculate_schedule_reservation_state(
  text, text, timestamptz, integer, text, uuid
) is
'Internal service-only helper computing conflicts and distinct daily/weekly capacity from one materialized reservation scan; invalid inputs fail closed with NULL results.';

revoke all on function public.calculate_schedule_reservation_state(
  text, text, timestamptz, integer, text, uuid
)
from public, anon, authenticated;

grant execute on function public.calculate_schedule_reservation_state(
  text, text, timestamptz, integer, text, uuid
)
to service_role;

do $migration$
begin
  if exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant execute on function public.calculate_schedule_reservation_state(
      text, text, timestamptz, integer, text, uuid
    ) to creator_dashboard_reader;
  end if;
end;
$migration$;

create or replace view public.looker_content_aware_hybrid_shadow_schedule
with (security_invoker = false)
as
with recursive valid_settings as (
  select
    s.platform,
    s.content_format,
    s.posts_per_week,
    s.max_posts_per_day,
    s.min_gap_hours,
    s.protected_hours,
    s.timezone_name
  from public.scheduling_cadence_settings s
  where s.is_active = true
    and s.content_format = 'short_form'
    and s.posts_per_week > 0
    and s.max_posts_per_day > 0
    and s.min_gap_hours > 0
    and s.protected_hours >= 0
    and nullif(trim(s.timezone_name), '') is not null
    and exists (
      select 1
      from pg_catalog.pg_timezone_names tz
      where tz.name = s.timezone_name
    )
),

movable_posts as (
  select
    sh.*,
    p.buffer_channel_id,
    s.posts_per_week,
    s.max_posts_per_day,
    s.min_gap_hours,
    s.protected_hours,
    row_number() over (
      partition by p.buffer_channel_id
      order by
        sh.current_buffer_due_at_utc,
        sh.buffer_post_id
    )::integer as channel_post_sequence
  from public.looker_content_aware_shadow_schedule sh
  join public.posts p
    on p.buffer_post_id = sh.buffer_post_id
  join public.channels c
    on c.buffer_channel_id = p.buffer_channel_id
  join valid_settings s
    on s.platform = sh.platform
   and s.content_format = sh.content_format
  where p.status = 'scheduled'
    and p.due_at is not null
    and p.schedule_evaluated_at is null
    and nullif(trim(p.buffer_channel_id), '') is not null
    and nullif(trim(c.service), '') is not null
    and lower(trim(c.service)) = lower(trim(sh.platform))
    and not exists (
      select 1
      from public.schedule_change_proposals history
      where history.buffer_post_id = p.buffer_post_id
    )
),

queued_posts_base as (
  select
    m.*,
    (
      ((m.channel_post_sequence - 1) / m.posts_per_week) + 1
    )::integer as cadence_cycle
  from movable_posts m
),

ordered_posts as (
  select
    q.*,
    row_number() over (
      partition by q.buffer_channel_id, q.cadence_cycle
      order by
        case
          when q.selected_model_level = 'Platform Overall' then 1
          else 0
        end,
        q.selected_model_priority asc nulls last,
        q.content_recommendation_score desc nulls last,
        q.channel_post_sequence,
        q.buffer_post_id
    )::integer as assignment_sequence
  from queued_posts_base q
),

calendar_dates as (
  select distinct
    p.buffer_channel_id,
    p.platform,
    p.content_format,
    p.timezone_name,
    p.protected_hours,
    gs.local_timestamp::date as local_date
  from ordered_posts p
  cross join lateral generate_series(
    ((now() at time zone p.timezone_name)::date + 2)::timestamp,
    ((now() at time zone p.timezone_name)::date + 23)::timestamp,
    interval '1 day'
  ) as gs(local_timestamp)
),

future_slots_numbered as (
  select
    c.buffer_channel_id,
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
    c.local_date + w.scheduled_time_local as proposed_at_local,
    (
      c.local_date + w.scheduled_time_local
    ) at time zone w.timezone_name as proposed_at_utc,
    row_number() over (
      partition by c.buffer_channel_id
      order by
        c.local_date,
        w.scheduled_time_local,
        w.slot_rank
    )::integer as slot_sequence
  from public.looker_weekly_slot_plan w
  join calendar_dates c
    on c.platform = w.platform
   and c.content_format = w.content_format
   and extract(isodow from c.local_date)::integer = w.publish_iso_day
  where (
    c.local_date + w.scheduled_time_local
  ) at time zone w.timezone_name >
    now() + make_interval(hours => c.protected_hours)
),

future_slots as (
  select
    f.*,
    (
      ((f.slot_sequence - 1) / p.posts_per_week) + 1
    )::integer as cadence_cycle,
    (
      ((f.slot_sequence - 1) % p.posts_per_week) + 1
    )::integer as cycle_slot_position,
    (
      f.buffer_channel_id
      || ':'
      || to_char(f.proposed_at_utc at time zone 'UTC',
                 'YYYY-MM-DD"T"HH24:MI:SS')
      || 'Z'
    )::text as slot_instance_key
  from future_slots_numbered f
  join (
    select distinct
      buffer_channel_id,
      posts_per_week
    from ordered_posts
  ) p
    on p.buffer_channel_id = f.buffer_channel_id
),

candidate_components as (
  select
    p.platform,
    p.buffer_channel_id,
    p.buffer_post_id,
    p.cadence_cycle,
    p.assignment_sequence,
    p.posts_per_week,
    p.max_posts_per_day,
    p.min_gap_hours,
    p.timezone_name,
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
    f.recommendation_score as platform_slot_recommendation_score,
    f.confidence as platform_slot_confidence,
    f.supporting_sample_size as platform_slot_supporting_sample_size,
    f.metrics_status as platform_slot_metrics_status,
    f.proposed_at_local,
    f.proposed_at_utc,
    (f.publish_iso_day = p.content_publish_iso_day) as content_day_matches,
    (f.recommended_window = p.content_recommended_window)
      as content_window_matches,
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
        abs(f.scheduled_hour_local - p.content_target_hour_local),
        24 - abs(f.scheduled_hour_local - p.content_target_hour_local)
      )
    end::integer as content_hour_distance,
    (
      reservation_state.reservation_conflict_count > 0
    ) as has_reservation_conflict,
    reservation_state.fixed_daily_reservation_count,
    reservation_state.fixed_weekly_reservation_count,
    (
      reservation_state.fixed_daily_reservation_count + 1
      <= p.max_posts_per_day
    ) as has_fixed_daily_capacity,
    (
      reservation_state.fixed_weekly_reservation_count + 1
      <= p.posts_per_week
    ) as has_fixed_weekly_capacity
  from ordered_posts p
  join future_slots f
    on f.buffer_channel_id = p.buffer_channel_id
   and f.platform = p.platform
   and f.content_format = p.content_format
   and f.cadence_cycle = p.cadence_cycle
  cross join lateral public.calculate_schedule_reservation_state(
    p.buffer_post_id,
    p.buffer_channel_id,
    f.proposed_at_utc,
    p.min_gap_hours,
    p.timezone_name,
    null
  ) reservation_state
),

candidate_scores as (
  select
    c.*,
    (
      case
        when c.content_day_matches and c.content_window_matches then 1000
        else 0
      end
      + case when c.content_day_matches then 260 else 0 end
      + case when c.content_window_matches then 220 else 0 end
      + greatest(0, 120 - (c.content_day_distance * 30))
      + greatest(0, 80 - (c.content_hour_distance * 6))
      + coalesce(c.platform_slot_recommendation_score, 0)
      - (coalesce(c.slot_rank, 99) * 0.10)
      - (c.cycle_slot_position * 0.01)
    )::numeric(12,2) as hybrid_assignment_score
  from candidate_components c
),

candidate_stats as (
  select
    c.buffer_post_id,
    count(*)::integer as candidate_slot_count,
    count(*) filter (
      where not c.has_reservation_conflict
    )::integer as collision_free_slot_count,
    count(*) filter (
      where c.has_reservation_conflict
    )::integer as excluded_collision_slot_count,
    count(*) filter (
      where not c.has_reservation_conflict
        and c.has_fixed_daily_capacity
        and c.has_fixed_weekly_capacity
    )::integer as capacity_safe_slot_count,
    count(*) filter (
      where not c.has_fixed_daily_capacity
    )::integer as excluded_daily_capacity_slot_count,
    count(*) filter (
      where not c.has_fixed_weekly_capacity
    )::integer as excluded_weekly_capacity_slot_count
  from candidate_components c
  group by c.buffer_post_id
),

safe_candidate_scores as (
  select c.*
  from candidate_scores c
  where not c.has_reservation_conflict
    and c.has_fixed_daily_capacity
    and c.has_fixed_weekly_capacity
),

assignments as (
  select
    p.buffer_channel_id,
    p.cadence_cycle,
    p.assignment_sequence,
    p.buffer_post_id,
    c.slot_instance_key,
    case
      when c.slot_instance_key is null then array[]::text[]
      else array[c.slot_instance_key]::text[]
    end as used_slot_keys,
    case
      when c.proposed_at_utc is null then array[]::timestamptz[]
      else array[c.proposed_at_utc]::timestamptz[]
    end as used_slot_times
  from ordered_posts p
  left join lateral (
    select
      cs.slot_instance_key,
      cs.proposed_at_utc
    from safe_candidate_scores cs
    where cs.buffer_post_id = p.buffer_post_id
    order by
      cs.hybrid_assignment_score desc,
      cs.source_recommendation_rank,
      cs.slot_rank,
      cs.slot_sequence
    limit 1
  ) c on true
  where p.assignment_sequence = 1

  union all

  select
    p.buffer_channel_id,
    p.cadence_cycle,
    p.assignment_sequence,
    p.buffer_post_id,
    c.slot_instance_key,
    case
      when c.slot_instance_key is null then a.used_slot_keys
      else array_append(a.used_slot_keys, c.slot_instance_key)
    end as used_slot_keys,
    case
      when c.proposed_at_utc is null then a.used_slot_times
      else array_append(a.used_slot_times, c.proposed_at_utc)
    end as used_slot_times
  from assignments a
  join ordered_posts p
    on p.buffer_channel_id = a.buffer_channel_id
   and p.cadence_cycle = a.cadence_cycle
   and p.assignment_sequence = a.assignment_sequence + 1
  left join lateral (
    select
      cs.slot_instance_key,
      cs.proposed_at_utc
    from safe_candidate_scores cs
    where cs.buffer_post_id = p.buffer_post_id
      and not (cs.slot_instance_key = any(a.used_slot_keys))
      and not exists (
        select 1
        from unnest(a.used_slot_times) used(used_at_utc)
        where used.used_at_utc >
                cs.proposed_at_utc
                - make_interval(hours => p.min_gap_hours)
          and used.used_at_utc <
                cs.proposed_at_utc
                + make_interval(hours => p.min_gap_hours)
      )
      and cs.fixed_daily_reservation_count
          + 1
          + (
            select count(*)::integer
            from unnest(a.used_slot_times) used(used_at_utc)
            where (
              used.used_at_utc at time zone cs.timezone_name
            )::date = cs.proposed_at_local::date
          ) <= cs.max_posts_per_day
      and cs.fixed_weekly_reservation_count
          + 1
          + (
            select count(*)::integer
            from unnest(a.used_slot_times) used(used_at_utc)
            where date_trunc(
              'week',
              used.used_at_utc at time zone cs.timezone_name
            ) = date_trunc('week', cs.proposed_at_local)
          ) <= cs.posts_per_week
    order by
      cs.hybrid_assignment_score desc,
      cs.source_recommendation_rank,
      cs.slot_rank,
      cs.slot_sequence
    limit 1
  ) c on true
),

raw_assignments as (
  select
    p.buffer_post_id,
    p.platform,
    p.content_format,
    p.channel_post_sequence as post_sequence,
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
    cs.cycle_slot_position as hybrid_cycle_slot_position,
    cs.slot_rank as hybrid_slot_rank,
    cs.source_recommendation_rank as hybrid_source_recommendation_rank,
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
    cs.fixed_daily_reservation_count,
    cs.fixed_weekly_reservation_count,
    p.posts_per_week,
    p.max_posts_per_day,
    p.min_gap_hours,
    p.protected_hours,
    p.timezone_name,
    p.buffer_channel_id,
    coalesce(stats.candidate_slot_count, 0) as candidate_slot_count,
    coalesce(stats.collision_free_slot_count, 0)
      as collision_free_slot_count,
    coalesce(stats.excluded_collision_slot_count, 0)
      as excluded_collision_slot_count,
    coalesce(stats.capacity_safe_slot_count, 0)
      as capacity_safe_slot_count,
    coalesce(stats.excluded_daily_capacity_slot_count, 0)
      as excluded_daily_capacity_slot_count,
    coalesce(stats.excluded_weekly_capacity_slot_count, 0)
      as excluded_weekly_capacity_slot_count
  from ordered_posts p
  left join assignments a
    on a.buffer_channel_id = p.buffer_channel_id
   and a.cadence_cycle = p.cadence_cycle
   and a.assignment_sequence = p.assignment_sequence
   and a.buffer_post_id = p.buffer_post_id
  left join safe_candidate_scores cs
    on cs.buffer_post_id = p.buffer_post_id
   and cs.slot_instance_key = a.slot_instance_key
  left join candidate_stats stats
    on stats.buffer_post_id = p.buffer_post_id
),

guardrail_inputs as (
  select
    r.*,
    count(*) filter (
      where r.hybrid_proposed_at_local is not null
    ) over (
      partition by
        r.buffer_channel_id,
        r.hybrid_proposed_at_local::date
    )::integer as new_batch_posts_that_day,
    count(*) filter (
      where r.hybrid_proposed_at_local is not null
    ) over (
      partition by
        r.buffer_channel_id,
        date_trunc('week', r.hybrid_proposed_at_local)
    )::integer as new_batch_posts_that_week,
    lag(r.hybrid_proposed_at_utc) over (
      partition by r.buffer_channel_id
      order by
        r.hybrid_proposed_at_utc nulls last,
        r.buffer_post_id
    ) as previous_hybrid_proposed_at_utc
  from raw_assignments r
),

capacity_guardrails as (
  select
    g.*,
    case
      when g.hybrid_proposed_at_utc is null then null::integer
      else
        g.fixed_daily_reservation_count
        + g.new_batch_posts_that_day
    end as hybrid_posts_that_day,
    case
      when g.hybrid_proposed_at_utc is null then null::integer
      else
        g.fixed_weekly_reservation_count
        + g.new_batch_posts_that_week
    end as hybrid_posts_that_week
  from guardrail_inputs g
),

finalized as (
  select
    g.*,
    (
      extract(epoch from (
        g.hybrid_proposed_at_utc
        - g.previous_hybrid_proposed_at_utc
      )) / 3600.0
    ) as hybrid_gap_hours_raw
  from capacity_guardrails g
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
    when content_day_matches and content_window_matches then
      'Exact content day + window'
    when content_day_matches then
      'Preferred content day; alternate window'
    when content_window_matches then
      'Preferred content window; alternate day'
    else
      'Nearby platform slot'
  end::text as content_match_class,
  hybrid_posts_that_day,
  round(hybrid_gap_hours_raw::numeric, 1) as hybrid_gap_hours,
  case
    when hybrid_proposed_at_local is null
         and candidate_slot_count > 0
         and collision_free_slot_count = 0 then
      'Review: every cadence-cycle slot conflicts with a same-channel reservation'
    when hybrid_proposed_at_local is null
         and candidate_slot_count > 0
         and capacity_safe_slot_count = 0 then
      'Review: fixed reservations consume all daily or weekly capacity'
    when hybrid_proposed_at_local is null then
      'Review: no slot available inside cadence cycle'
    when hybrid_posts_that_day > max_posts_per_day then
      'Review: maximum posts per day would be exceeded'
    when hybrid_posts_that_week > posts_per_week then
      'Review: weekly posting capacity would be exceeded'
    when hybrid_gap_hours_raw is not null
         and hybrid_gap_hours_raw < min_gap_hours then
      'Review: minimum same-channel gap would be violated'
    else
      'Pass'
  end::text as hybrid_guardrail_status,
  case
    when hybrid_proposed_at_local is null then
      'No hybrid assignment'
    when platform_plan_proposed_at_local
         is not distinct from hybrid_proposed_at_local then
      'Same exact platform-plan slot'
    when platform_plan_publish_iso_day = hybrid_publish_iso_day
         and platform_plan_window = hybrid_recommended_window then
      'Same platform-plan recommendation window'
    else
      'Reassigned inside the same cadence cycle'
  end::text as platform_plan_comparison,
  (
    platform_plan_proposed_at_local
    is not distinct from hybrid_proposed_at_local
  ) as exact_platform_plan_match,
  round((
    extract(epoch from (
      hybrid_proposed_at_utc - platform_plan_proposed_at_utc
    )) / 3600.0
  )::numeric, 1) as platform_plan_shift_hours,
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
    and hybrid_posts_that_week <= posts_per_week
    and (
      hybrid_gap_hours_raw is null
      or hybrid_gap_hours_raw >= min_gap_hours
    )
  ) as shadow_ready_for_live_test,
  max_posts_per_day,
  min_gap_hours,
  protected_hours,
  timezone_name,

  -- Appended migration-029 diagnostics. Existing columns above are unchanged.
  buffer_channel_id,
  true::boolean as is_movable,
  candidate_slot_count,
  collision_free_slot_count,
  excluded_collision_slot_count,
  (hybrid_proposed_at_utc is not null)::boolean
    as reservation_collision_free,
  case
    when candidate_slot_count = 0 then
      'No weekly-template slot exists inside the cadence cycle'
    when collision_free_slot_count = 0 then
      'Every cadence-cycle slot is inside the configured same-channel minimum gap'
    when capacity_safe_slot_count = 0 then
      'Every collision-free cadence-cycle slot exceeds fixed daily or weekly capacity'
    when hybrid_proposed_at_utc is null then
      'Collision-free slots existed but none remained after batch assignment'
    else null
  end::text as collision_blocking_reason,

  -- Appended fixed-capacity diagnostics.
  posts_per_week as configured_posts_per_week,
  fixed_daily_reservation_count,
  fixed_weekly_reservation_count,
  new_batch_posts_that_day,
  new_batch_posts_that_week,
  hybrid_posts_that_week,
  capacity_safe_slot_count,
  excluded_daily_capacity_slot_count,
  excluded_weekly_capacity_slot_count,
  case
    when hybrid_proposed_at_utc is null
         and capacity_safe_slot_count = 0 then
      'No collision-free slot has remaining daily and weekly capacity'
    when hybrid_posts_that_day > max_posts_per_day then
      'Selected target exceeds fixed plus batch daily capacity'
    when hybrid_posts_that_week > posts_per_week then
      'Selected target exceeds fixed plus batch weekly capacity'
    else null
  end::text as capacity_blocking_reason
from finalized;



create or replace view public.looker_content_aware_proposal_preview
with (security_invoker = false)
as
with active_proposals as (
  select distinct on (proposal.buffer_post_id)
    proposal.buffer_post_id,
    proposal.id as active_proposal_id,
    proposal.approval_status as active_proposal_status,
    proposal.proposed_due_at_utc as active_proposed_due_at_utc,
    proposal.proposed_due_at_local as active_proposed_due_at_local,
    proposal.generated_at as active_proposal_generated_at,
    proposal.updated_at as active_proposal_updated_at
  from public.schedule_change_proposals proposal
  where proposal.approval_status in ('Pending', 'Approved')
  order by
    proposal.buffer_post_id,
    proposal.updated_at desc,
    proposal.generated_at desc,
    proposal.id desc
),

preview_base as (
  select
    h.*,
    ap.active_proposal_id,
    ap.active_proposal_status,
    ap.active_proposed_due_at_utc,
    ap.active_proposed_due_at_local,
    ap.active_proposal_generated_at,
    ap.active_proposal_updated_at,
    case
      when h.selected_model_level = 'Platform Overall' then
        coalesce(
          h.platform_slot_recommendation_score,
          h.platform_plan_score
        )
      else
        coalesce(
          h.content_recommendation_score,
          h.platform_slot_recommendation_score,
          h.platform_plan_score
        )
    end as proposal_recommendation_score,
    case
      when h.selected_model_level = 'Platform Overall' then
        coalesce(
          h.platform_slot_confidence,
          h.platform_plan_confidence
        )
      else
        coalesce(
          h.content_confidence,
          h.platform_slot_confidence,
          h.platform_plan_confidence
        )
    end as proposal_confidence,
    case
      when h.selected_model_level = 'Platform Overall' then
        coalesce(
          h.platform_slot_supporting_sample_size,
          h.platform_plan_supporting_sample_size,
          0
        )
      else
        coalesce(
          h.group_sample_size,
          h.platform_slot_supporting_sample_size,
          h.platform_plan_supporting_sample_size,
          0
        )
    end as proposal_supporting_sample_size,
    case
      when h.selected_model_level = 'Platform Overall' then
        coalesce(
          h.platform_slot_metrics_status,
          h.platform_plan_metrics_status
        )
      else
        coalesce(
          h.content_metrics_status,
          h.platform_slot_metrics_status,
          h.platform_plan_metrics_status
        )
    end as proposal_metrics_status,
    p.status as current_post_status,
    p.due_at as synchronized_due_at_utc,
    c.service as channel_service,
    settings.is_active as cadence_is_active,
    settings.posts_per_week as current_posts_per_week,
    settings.max_posts_per_day as current_max_posts_per_day,
    settings.min_gap_hours as current_min_gap_hours,
    settings.protected_hours as current_protected_hours,
    settings.timezone_name as current_timezone_name,
    (
      nullif(trim(p.buffer_channel_id), '') is not null
      and nullif(trim(c.service), '') is not null
      and lower(trim(c.service)) = lower(trim(h.platform))
    ) as channel_identity_valid,
    (
      settings.platform is not null
      and settings.is_active = true
      and settings.posts_per_week > 0
      and settings.max_posts_per_day > 0
      and settings.min_gap_hours > 0
      and settings.protected_hours >= 0
      and nullif(trim(settings.timezone_name), '') is not null
      and exists (
        select 1
        from pg_catalog.pg_timezone_names tz
        where tz.name = settings.timezone_name
      )
    ) as cadence_configuration_valid,
    case
      when nullif(trim(p.buffer_channel_id), '') is null
        or settings.min_gap_hours is null
        or settings.min_gap_hours <= 0
        or h.hybrid_proposed_at_utc is null
      then null::integer
      else reservation_state.reservation_conflict_count
    end as current_reservation_conflict_count,
    case
      when nullif(trim(p.buffer_channel_id), '') is null
        or settings.platform is null
        or settings.is_active is distinct from true
        or settings.posts_per_week is null
        or settings.posts_per_week <= 0
        or settings.max_posts_per_day is null
        or settings.max_posts_per_day <= 0
        or nullif(trim(settings.timezone_name), '') is null
        or not exists (
          select 1
          from pg_catalog.pg_timezone_names tz
          where tz.name = settings.timezone_name
        )
        or h.hybrid_proposed_at_utc is null
      then null::integer
      else reservation_state.fixed_daily_reservation_count
    end as current_fixed_daily_reservation_count,
    case
      when nullif(trim(p.buffer_channel_id), '') is null
        or settings.platform is null
        or settings.is_active is distinct from true
        or settings.posts_per_week is null
        or settings.posts_per_week <= 0
        or settings.max_posts_per_day is null
        or settings.max_posts_per_day <= 0
        or nullif(trim(settings.timezone_name), '') is null
        or not exists (
          select 1
          from pg_catalog.pg_timezone_names tz
          where tz.name = settings.timezone_name
        )
        or h.hybrid_proposed_at_utc is null
      then null::integer
      else reservation_state.fixed_weekly_reservation_count
    end as current_fixed_weekly_reservation_count
  from public.looker_content_aware_hybrid_shadow_schedule h
  join public.posts p
    on p.buffer_post_id = h.buffer_post_id
  left join public.channels c
    on c.buffer_channel_id = p.buffer_channel_id
  left join public.scheduling_cadence_settings settings
    on settings.platform = h.platform
   and settings.content_format = h.content_format
  left join active_proposals ap
    on ap.buffer_post_id = h.buffer_post_id
  cross join lateral public.calculate_schedule_reservation_state(
    h.buffer_post_id,
    p.buffer_channel_id,
    h.hybrid_proposed_at_utc,
    settings.min_gap_hours,
    settings.timezone_name,
    null
  ) reservation_state
  where h.current_buffer_due_at_utc
    is distinct from h.hybrid_proposed_at_utc
),

preview_ready as (
  select
    pb.*,
    (
      coalesce(pb.shadow_ready_for_live_test, false)
      and coalesce(pb.recommendation_ready_for_preview, false)
      and pb.hybrid_guardrail_status = 'Pass'
      and coalesce(pb.stayed_inside_cadence_cycle, false)
      and pb.active_proposal_id is null
      and pb.current_post_status = 'scheduled'
      and pb.synchronized_due_at_utc
            is not distinct from pb.current_buffer_due_at_utc
      and pb.channel_identity_valid
      and pb.cadence_configuration_valid
      and pb.current_reservation_conflict_count = 0
      and pb.current_fixed_daily_reservation_count + 1
            <= pb.current_max_posts_per_day
      and pb.current_fixed_weekly_reservation_count + 1
            <= pb.current_posts_per_week
    ) as ready_to_create,
    case
      when pb.active_proposal_id is not null then
        'Blocked: active '
        || pb.active_proposal_status
        || ' proposal already exists'
      when pb.current_post_status is distinct from 'scheduled' then
        'Blocked: post is no longer scheduled'
      when pb.synchronized_due_at_utc is null then
        'Blocked: synchronized current due time is missing'
      when pb.synchronized_due_at_utc
           is distinct from pb.current_buffer_due_at_utc then
        'Blocked: synchronized current due time changed after preview'
      when not coalesce(pb.channel_identity_valid, false) then
        'Blocked: Buffer channel identity is missing or does not match platform'
      when not coalesce(pb.cadence_configuration_valid, false) then
        'Blocked: cadence, protected-hours, minimum-gap, or timezone configuration is missing or invalid'
      when coalesce(pb.current_reservation_conflict_count, 0) > 0 then
        'Blocked: proposed time violates the configured same-channel minimum gap'
      when pb.current_fixed_daily_reservation_count is null
        or pb.current_fixed_weekly_reservation_count is null then
        'Blocked: current fixed reservation capacity could not be evaluated'
      when pb.current_fixed_daily_reservation_count + 1
           > pb.current_max_posts_per_day then
        'Blocked: fixed reservations plus this target exceed daily channel capacity'
      when pb.current_fixed_weekly_reservation_count + 1
           > pb.current_posts_per_week then
        'Blocked: fixed reservations plus this target exceed weekly channel capacity'
      when not coalesce(pb.shadow_ready_for_live_test, false) then
        'Blocked: hybrid shadow row is not ready for live testing'
      when not coalesce(pb.recommendation_ready_for_preview, false) then
        'Blocked: recommendation is not ready for preview'
      when pb.hybrid_guardrail_status is distinct from 'Pass' then
        'Blocked: hybrid guardrail status is '
        || coalesce(pb.hybrid_guardrail_status, '(missing)')
      when not coalesce(pb.stayed_inside_cadence_cycle, false) then
        'Blocked: proposed time left the assigned cadence cycle'
      else null
    end::text as blocking_reason
  from preview_base pb
)

select
  md5(concat_ws(
    '|',
    pr.buffer_post_id,
    pr.hybrid_proposed_at_utc::text,
    pr.selected_model_level,
    pr.content_match_class
  )) as preview_key,
  pr.buffer_post_id,
  pr.platform,
  pr.content_format,
  pr.post_text,
  pr.external_link,
  pr.current_buffer_due_at_utc as current_due_at_utc,
  pr.current_buffer_due_at_local as current_due_at_local,
  pr.hybrid_proposed_at_utc as proposed_due_at_utc,
  pr.hybrid_proposed_at_local as proposed_due_at_local,
  pr.hybrid_slot_rank as slot_rank,
  pr.hybrid_source_recommendation_rank as source_recommendation_rank,
  pr.proposal_recommendation_score as recommendation_score,
  pr.proposal_confidence as confidence,
  pr.proposal_supporting_sample_size as supporting_sample_size,
  pr.proposal_metrics_status as metrics_status,
  pr.timezone_name,
  'Pending'::text as approval_status,
  null::timestamptz as approved_at,
  null::timestamptz as rejected_at,
  null::timestamptz as applied_at,
  null::text as result_message,
  null::text as error_message,
  now() as generated_at,
  now() as updated_at,
  null::timestamptz as sheet_exported_at,
  pr.ready_to_create,
  case when pr.ready_to_create then 'Ready' else 'Blocked' end
    as preview_status,
  pr.blocking_reason,
  (pr.active_proposal_id is not null) as has_active_proposal,
  pr.active_proposal_id,
  pr.active_proposal_status,
  pr.active_proposed_due_at_utc,
  pr.active_proposed_due_at_local,
  pr.active_proposal_generated_at,
  pr.active_proposal_updated_at,
  pr.clip_group,
  pr.game,
  pr.content_type,
  pr.vibe,
  pr.hook_type,
  pr.labels_complete,
  pr.selected_model_level,
  pr.selected_model_priority,
  pr.selected_content_group,
  pr.group_sample_size,
  pr.minimum_sample_size,
  pr.fallback_reason,
  pr.platform_plan_proposed_at_utc,
  pr.platform_plan_proposed_at_local,
  pr.platform_plan_window,
  pr.platform_plan_score,
  pr.platform_plan_confidence,
  pr.content_recommended_slot,
  pr.content_recommendation_score,
  pr.content_confidence,
  pr.content_metrics_status,
  pr.content_match_class,
  pr.content_day_matches,
  pr.content_window_matches,
  pr.content_day_distance,
  pr.content_hour_distance,
  pr.hybrid_assignment_score,
  pr.platform_plan_comparison,
  pr.exact_platform_plan_match,
  pr.platform_plan_shift_hours,
  pr.post_sequence,
  pr.cadence_cycle,
  pr.assignment_sequence,
  pr.hybrid_slot_sequence,
  pr.hybrid_cycle_slot_position,
  pr.hybrid_publish_iso_day,
  pr.hybrid_publish_day_name,
  pr.hybrid_hour_local,
  pr.hybrid_time_local,
  pr.hybrid_recommended_window,
  pr.hybrid_posts_that_day,
  pr.hybrid_gap_hours,
  pr.hybrid_guardrail_status,
  pr.stayed_inside_cadence_cycle,
  pr.shadow_ready_for_live_test,
  pr.recommendation_ready_for_preview,
  pr.max_posts_per_day,
  pr.min_gap_hours,
  pr.protected_hours,

  -- Appended migration-029 diagnostics.
  pr.buffer_channel_id,
  pr.channel_service,
  pr.channel_identity_valid,
  pr.cadence_configuration_valid,
  pr.current_reservation_conflict_count,
  pr.synchronized_due_at_utc,
  pr.current_min_gap_hours as configured_min_gap_hours,
  pr.current_protected_hours as configured_protected_hours,
  pr.current_timezone_name as configured_timezone_name,
  pr.candidate_slot_count,
  pr.collision_free_slot_count,
  pr.excluded_collision_slot_count,
  pr.collision_blocking_reason,
  pr.current_fixed_daily_reservation_count,
  pr.current_fixed_weekly_reservation_count,
  (pr.current_fixed_daily_reservation_count + 1)::integer
    as projected_daily_post_count,
  (pr.current_fixed_weekly_reservation_count + 1)::integer
    as projected_weekly_post_count,
  pr.current_posts_per_week as configured_posts_per_week,
  pr.capacity_safe_slot_count,
  pr.excluded_daily_capacity_slot_count,
  pr.excluded_weekly_capacity_slot_count,
  pr.capacity_blocking_reason
from preview_ready pr;



do $migration$
declare
  v_mismatch text;
  v_contract text[];
  v_definition text;
begin
  select string_agg(
    format('%s contract changed', snapshot.relname),
    '; ' order by snapshot.relname
  )
  into v_mismatch
  from migration_031_replaced_view_contract snapshot
  join pg_catalog.pg_class current_relation
    on current_relation.oid = snapshot.relation_oid
  where current_relation.relowner is distinct from snapshot.relowner
     or current_relation.relacl is distinct from snapshot.relacl
     or current_relation.reloptions is distinct from snapshot.reloptions
     or snapshot.column_contract is distinct from (
       select array_agg(
         format(
           '%s:%s',
           attribute.attname,
           pg_catalog.format_type(
             attribute.atttypid,
             attribute.atttypmod
           )
         )
         order by attribute.attnum
       )
       from pg_catalog.pg_attribute attribute
       where attribute.attrelid = current_relation.oid
         and attribute.attnum > 0
         and not attribute.attisdropped
     );

  if v_mismatch is not null then
    raise exception
      'Migration 031 changed a replaced view contract: %',
      v_mismatch;
  end if;

  select lower(pg_catalog.pg_get_viewdef(
    'public.looker_content_aware_hybrid_shadow_schedule'::regclass,
    true
  ))
  into v_definition;

  if regexp_count(
       v_definition,
       'calculate_schedule_reservation_state'
     ) <> 1
     or position('find_schedule_slot_conflicts' in v_definition) > 0
     or position('get_schedule_reservation_capacity' in v_definition) > 0 then
    raise exception
      'Hybrid scheduler did not consolidate reservation calculations exactly once';
  end if;

  select lower(pg_catalog.pg_get_viewdef(
    'public.looker_content_aware_proposal_preview'::regclass,
    true
  ))
  into v_definition;

  if regexp_count(
       v_definition,
       'calculate_schedule_reservation_state'
     ) <> 1
     or position('find_schedule_slot_conflicts' in v_definition) > 0
     or position('get_schedule_reservation_capacity' in v_definition) > 0 then
    raise exception
      'Proposal preview did not consolidate reservation calculations exactly once';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc function_record
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_record.pronamespace
    where namespace.nspname = 'public'
      and function_record.oid =
        'public.calculate_schedule_reservation_state(text,text,timestamptz,integer,text,uuid)'
          ::regprocedure
      and function_record.provolatile = 's'
      and function_record.prosecdef
      and function_record.proretset
      and function_record.prorows = 1
      and function_record.proconfig @>
          array['search_path=""']::text[]
  ) then
    raise exception
      'Internal reservation-state helper metadata is not exact';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.calculate_schedule_reservation_state(text,text,timestamptz,integer,text,uuid)',
    'EXECUTE'
  ) then
    raise exception
      'service_role is missing internal helper EXECUTE';
  end if;

  if exists (
       select 1
       from pg_catalog.pg_roles
       where rolname = 'creator_dashboard_reader'
     )
     and not has_function_privilege(
       'creator_dashboard_reader',
       'public.calculate_schedule_reservation_state(text,text,timestamptz,integer,text,uuid)',
       'EXECUTE'
     ) then
    raise exception
      'creator_dashboard_reader is missing reporting helper EXECUTE';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc function_record
    cross join lateral aclexplode(
      coalesce(
        function_record.proacl,
        acldefault('f', function_record.proowner)
      )
    ) acl
    left join pg_catalog.pg_roles grantee
      on grantee.oid = acl.grantee
    where function_record.oid =
      'public.calculate_schedule_reservation_state(text,text,timestamptz,integer,text,uuid)'
        ::regprocedure
      and acl.privilege_type = 'EXECUTE'
      and (
        acl.grantee = 0::oid
        or grantee.rolname in (
          'anon',
          'authenticated'
        )
      )
  ) then
    raise exception
      'Internal helper is exposed to a non-service role';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index index_record
    where index_record.indexrelid =
          'public.schedule_change_proposals_buffer_post_id_idx'::regclass
      and index_record.indrelid =
          'public.schedule_change_proposals'::regclass
      and index_record.indisvalid
      and index_record.indisready
      and not index_record.indisunique
      and index_record.indpred is null
      and (
        select array_agg(
          attribute.attname
          order by key_column.ordinality
        )
        from unnest(index_record.indkey::smallint[])
          with ordinality key_column(attnum, ordinality)
        join pg_catalog.pg_attribute attribute
          on attribute.attrelid = index_record.indrelid
         and attribute.attnum = key_column.attnum
        where key_column.ordinality <= index_record.indnkeyatts
      ) = array['buffer_post_id']::name[]
  ) then
    raise exception
      'Full proposal-history lookup index is not exact';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index index_record
    where index_record.indexrelid =
          'public.posts_scheduled_channel_due_at_idx'::regclass
      and index_record.indrelid = 'public.posts'::regclass
      and index_record.indisvalid
      and index_record.indisready
      and not index_record.indisunique
      and (
        select array_agg(
          attribute.attname
          order by key_column.ordinality
        )
        from unnest(index_record.indkey::smallint[])
          with ordinality key_column(attnum, ordinality)
        join pg_catalog.pg_attribute attribute
          on attribute.attrelid = index_record.indrelid
         and attribute.attnum = key_column.attnum
        where key_column.ordinality <= index_record.indnkeyatts
      ) = array['buffer_channel_id', 'due_at']::name[]
      and lower(
        regexp_replace(
          pg_catalog.pg_get_expr(
            index_record.indpred,
            index_record.indrelid
          ),
          '\s+',
          '',
          'g'
        )
      ) = '((status=''scheduled''::text)and(due_atisnotnull))'
  ) then
    raise exception
      'Partial scheduled-reservation lookup index is not exact';
  end if;

  select array_agg(
    format('%s:%s:%s', column_name, data_type, udt_name)
    order by ordinal_position
  )
  into v_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if v_contract is distinct from array[
    'proposal_id:uuid:uuid',
    'buffer_post_id:text:text',
    'platform:text:text',
    'content_format:text:text',
    'post_text:text:text',
    'external_link:text:text',
    'current_due_at_utc:timestamp with time zone:timestamptz',
    'current_due_at_local:timestamp without time zone:timestamp',
    'proposed_due_at_utc:timestamp with time zone:timestamptz',
    'proposed_due_at_local:timestamp without time zone:timestamp',
    'slot_rank:integer:int4',
    'source_recommendation_rank:integer:int4',
    'recommendation_score:numeric:numeric',
    'confidence:text:text',
    'supporting_sample_size:integer:int4',
    'metrics_status:text:text',
    'timezone_name:text:text',
    'approval_status:text:text',
    'approved_at:timestamp with time zone:timestamptz'
  ]::text[] then
    raise exception
      'Migration 031 changed the Make-facing contract: %',
      v_contract;
  end if;
end;
$migration$;

commit;
