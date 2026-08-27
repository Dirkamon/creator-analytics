-- Creator Analytics
-- Optimize range-aware schedule proposal generation
-- File: Database/032_optimize_range_aware_schedule_proposal_generation.sql
--
-- Replaces only the internal collision-safe generator. The public wrappers,
-- reporting views, application preflight, Make-facing contract, and all
-- permissions remain unchanged.

begin;

create temporary table migration_032_generator_contract
on commit drop
as
select
  function_record.oid,
  function_record.proowner,
  function_record.proacl,
  function_record.prosecdef,
  function_record.proconfig,
  function_record.provolatile,
  function_record.prorettype,
  function_record.proargtypes,
  pg_catalog.obj_description(function_record.oid, 'pg_proc') as description
from pg_catalog.pg_proc function_record
where function_record.oid =
  'public.create_collision_safe_schedule_proposals(integer,date,date)'
    ::regprocedure;

do $migration$
begin
  if (select count(*) from migration_032_generator_contract) <> 1 then
    raise exception
      'Migration 032 requires the migration-029 collision-safe generator';
  end if;
end;
$migration$;

create or replace function public.create_collision_safe_schedule_proposals(
  p_limit integer,
  p_start_date date,
  p_end_date date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_rows_created integer := 0;
begin
  if p_limit is not null
     and (p_limit < 1 or p_limit > 500) then
    raise exception 'p_limit must be NULL or between 1 and 500';
  end if;

  if p_start_date is not null
     and p_end_date is not null
     and p_end_date < p_start_date then
    raise exception 'p_end_date must not be earlier than p_start_date';
  end if;

  -- Preserve the transaction-scoped global generator lock from migration 029.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'creator-analytics-schedule-proposal-generation',
      0
    )
  );

  with recursive valid_settings as materialized (
    select
      settings.platform,
      settings.content_format,
      settings.posts_per_week,
      settings.max_posts_per_day,
      settings.min_gap_hours,
      settings.protected_hours,
      settings.timezone_name
    from public.scheduling_cadence_settings settings
    where settings.is_active = true
      and settings.content_format = 'short_form'
      and settings.posts_per_week > 0
      and settings.max_posts_per_day > 0
      and settings.min_gap_hours > 0
      and settings.protected_hours >= 0
      and nullif(pg_catalog.btrim(settings.timezone_name), '') is not null
      and exists (
        select 1
        from pg_catalog.pg_timezone_names timezone_record
        where timezone_record.name = settings.timezone_name
      )
  ),

  -- Preserve the migration-029 movable population and exact channel ordering.
  movable_posts as materialized (
    select
      shadow.*,
      post_record.buffer_channel_id,
      settings.posts_per_week,
      settings.max_posts_per_day,
      settings.min_gap_hours,
      settings.protected_hours,
      row_number() over (
        partition by post_record.buffer_channel_id
        order by
          shadow.current_buffer_due_at_utc,
          shadow.buffer_post_id
      )::integer as channel_post_sequence
    from public.looker_content_aware_shadow_schedule shadow
    join public.posts post_record
      on post_record.buffer_post_id = shadow.buffer_post_id
    join public.channels channel_record
      on channel_record.buffer_channel_id = post_record.buffer_channel_id
    join valid_settings settings
      on settings.platform = shadow.platform
     and settings.content_format = shadow.content_format
    where post_record.status = 'scheduled'
      and post_record.due_at is not null
      and post_record.schedule_evaluated_at is null
      and nullif(pg_catalog.btrim(post_record.buffer_channel_id), '')
            is not null
      and nullif(pg_catalog.btrim(channel_record.service), '') is not null
      and lower(pg_catalog.btrim(channel_record.service)) =
            lower(pg_catalog.btrim(shadow.platform))
      and not exists (
        select 1
        from public.schedule_change_proposals history
        where history.buffer_post_id = post_record.buffer_post_id
      )
  ),

  ordered_posts as materialized (
    select
      movable.*,
      (
        ((movable.channel_post_sequence - 1) / movable.posts_per_week) + 1
      )::integer as cadence_cycle,
      row_number() over (
        partition by
          movable.buffer_channel_id,
          (
            ((movable.channel_post_sequence - 1) / movable.posts_per_week) + 1
          )::integer
        order by
          case
            when movable.selected_model_level = 'Platform Overall' then 1
            else 0
          end,
          movable.selected_model_priority asc nulls last,
          movable.content_recommendation_score desc nulls last,
          movable.channel_post_sequence,
          movable.buffer_post_id
      )::integer as assignment_sequence
    from movable_posts movable
  ),

  -- Slot sequence is deliberately computed over the complete effective
  -- migration-029 calendar before applying the requested date range. This
  -- preserves cadence-cycle identities and exact scheduling choices.
  calendar_dates as materialized (
    select distinct
      post_record.buffer_channel_id,
      post_record.platform,
      post_record.content_format,
      post_record.timezone_name,
      post_record.protected_hours,
      generated.local_timestamp::date as local_date
    from ordered_posts post_record
    cross join lateral pg_catalog.generate_series(
      (
        (pg_catalog.now() at time zone post_record.timezone_name)::date + 2
      )::timestamp,
      (
        (pg_catalog.now() at time zone post_record.timezone_name)::date + 23
      )::timestamp,
      interval '1 day'
    ) generated(local_timestamp)
  ),

  future_slots_numbered as materialized (
    select
      calendar.buffer_channel_id,
      weekly.platform,
      weekly.content_format,
      weekly.slot_rank,
      weekly.source_recommendation_rank,
      weekly.publish_iso_day,
      weekly.publish_day_name,
      weekly.scheduled_hour_local,
      weekly.scheduled_time_local,
      weekly.recommended_window,
      weekly.recommendation_score,
      weekly.confidence,
      weekly.supporting_sample_size,
      weekly.metrics_status,
      weekly.timezone_name,
      calendar.local_date + weekly.scheduled_time_local
        as proposed_at_local,
      (
        calendar.local_date + weekly.scheduled_time_local
      ) at time zone weekly.timezone_name as proposed_at_utc,
      row_number() over (
        partition by calendar.buffer_channel_id
        order by
          calendar.local_date,
          weekly.scheduled_time_local,
          weekly.slot_rank
      )::integer as slot_sequence
    from public.looker_weekly_slot_plan weekly
    join calendar_dates calendar
      on calendar.platform = weekly.platform
     and calendar.content_format = weekly.content_format
     and extract(isodow from calendar.local_date)::integer =
           weekly.publish_iso_day
    where (
      calendar.local_date + weekly.scheduled_time_local
    ) at time zone weekly.timezone_name >
      pg_catalog.now()
      + pg_catalog.make_interval(hours => calendar.protected_hours)
  ),

  future_slots as materialized (
    select
      slot_record.*,
      (
        ((slot_record.slot_sequence - 1) / cadence.posts_per_week) + 1
      )::integer as cadence_cycle,
      (
        ((slot_record.slot_sequence - 1) % cadence.posts_per_week) + 1
      )::integer as cycle_slot_position,
      (
        slot_record.buffer_channel_id
        || ':'
        || pg_catalog.to_char(
             slot_record.proposed_at_utc at time zone 'UTC',
             'YYYY-MM-DD"T"HH24:MI:SS'
           )
        || 'Z'
      )::text as slot_instance_key
    from future_slots_numbered slot_record
    join (
      select distinct
        post_record.buffer_channel_id,
        post_record.posts_per_week
      from ordered_posts post_record
    ) cadence
      on cadence.buffer_channel_id = slot_record.buffer_channel_id
  ),

  requested_cycle_bounds as materialized (
    select
      slot_record.buffer_channel_id,
      min(slot_record.cadence_cycle)::integer as minimum_requested_cycle,
      max(slot_record.cadence_cycle)::integer as maximum_requested_cycle
    from future_slots slot_record
    where (
        p_start_date is null
        or slot_record.proposed_at_local::date >= p_start_date
      )
      and (
        p_end_date is null
        or slot_record.proposed_at_local::date <= p_end_date
      )
    group by slot_record.buffer_channel_id
  ),

  -- Neighboring cycles are retained as read/lock context. The preceding cycle
  -- supplies the exact cross-cycle LAG value; the following cycle preserves
  -- day/week window counts at a cycle boundary. Only requested dates can be
  -- inserted later.
  context_posts as materialized (
    select post_record.*
    from ordered_posts post_record
    join requested_cycle_bounds bounds
      on bounds.buffer_channel_id = post_record.buffer_channel_id
     and post_record.cadence_cycle between
           greatest(1, bounds.minimum_requested_cycle - 1)
           and bounds.maximum_requested_cycle + 1
  ),

  context_slots as materialized (
    select slot_record.*
    from future_slots slot_record
    join requested_cycle_bounds bounds
      on bounds.buffer_channel_id = slot_record.buffer_channel_id
     and slot_record.cadence_cycle between
           greatest(1, bounds.minimum_requested_cycle - 1)
           and bounds.maximum_requested_cycle + 1
  ),

  lock_targets as materialized (
    select distinct post_record.buffer_post_id
    from context_posts post_record
  ),

  -- Deterministic row locking narrows the lock set to range-relevant cadence
  -- cycles while retaining migration-029 current-state/history safeguards.
  locked_posts as materialized (
    select
      post_record.buffer_post_id,
      post_record.buffer_channel_id,
      post_record.status,
      post_record.due_at,
      post_record.schedule_evaluated_at
    from public.posts post_record
    join lock_targets target
      on target.buffer_post_id = post_record.buffer_post_id
    where post_record.status = 'scheduled'
      and post_record.due_at is not null
      and post_record.schedule_evaluated_at is null
      and not exists (
        select 1
        from public.schedule_change_proposals history
        where history.buffer_post_id = post_record.buffer_post_id
      )
    order by post_record.buffer_post_id
    for update of post_record
  ),

  locked_ordered_posts as materialized (
    select context.*
    from context_posts context
    join locked_posts locked
      on locked.buffer_post_id = context.buffer_post_id
     and locked.buffer_channel_id = context.buffer_channel_id
     and locked.status = 'scheduled'
     and locked.due_at is not null
     and locked.due_at = context.current_buffer_due_at_utc
     and locked.schedule_evaluated_at is null
    where not exists (
      select 1
      from public.schedule_change_proposals history
      where history.buffer_post_id = context.buffer_post_id
    )
  ),

  -- One authoritative reservation inventory is shared by every candidate in
  -- this generator statement. Applied targets awaiting later synchronization
  -- remain present through the unchanged migration-029 view.
  reservation_inventory as materialized (
    select reservation.*
    from public.schedule_slot_reservations reservation
    where reservation.buffer_channel_id in (
      select distinct post_record.buffer_channel_id
      from locked_ordered_posts post_record
    )
  ),

  candidate_basis as materialized (
    select
      post_record.platform,
      post_record.buffer_channel_id,
      post_record.buffer_post_id,
      post_record.cadence_cycle,
      post_record.assignment_sequence,
      post_record.posts_per_week,
      post_record.max_posts_per_day,
      post_record.min_gap_hours,
      post_record.protected_hours,
      post_record.timezone_name,
      slot_record.slot_instance_key,
      slot_record.slot_sequence,
      slot_record.cycle_slot_position,
      slot_record.slot_rank,
      slot_record.source_recommendation_rank,
      slot_record.publish_iso_day,
      slot_record.publish_day_name,
      slot_record.scheduled_hour_local,
      slot_record.scheduled_time_local,
      slot_record.recommended_window,
      slot_record.recommendation_score
        as platform_slot_recommendation_score,
      slot_record.confidence as platform_slot_confidence,
      slot_record.supporting_sample_size
        as platform_slot_supporting_sample_size,
      slot_record.metrics_status as platform_slot_metrics_status,
      slot_record.proposed_at_local,
      slot_record.proposed_at_utc,
      (slot_record.publish_iso_day = post_record.content_publish_iso_day)
        as content_day_matches,
      (slot_record.recommended_window =
         post_record.content_recommended_window)
        as content_window_matches,
      case
        when post_record.content_publish_iso_day is null then 3
        else least(
          abs(slot_record.publish_iso_day -
              post_record.content_publish_iso_day),
          7 - abs(slot_record.publish_iso_day -
                  post_record.content_publish_iso_day)
        )
      end::integer as content_day_distance,
      case
        when post_record.content_target_hour_local is null then 12
        else least(
          abs(slot_record.scheduled_hour_local -
              post_record.content_target_hour_local),
          24 - abs(slot_record.scheduled_hour_local -
                   post_record.content_target_hour_local)
        )
      end::integer as content_hour_distance
    from locked_ordered_posts post_record
    join context_slots slot_record
      on slot_record.buffer_channel_id = post_record.buffer_channel_id
     and slot_record.platform = post_record.platform
     and slot_record.content_format = post_record.content_format
     and slot_record.cadence_cycle = post_record.cadence_cycle
  ),

  -- Conflict rows remain non-distinct. Capacity rows retain migration-029's
  -- distinct (Buffer Post ID, reserved time) semantics.
  candidate_reservation_state as materialized (
    select
      candidate.buffer_post_id,
      candidate.slot_instance_key,
      count(reservation.reserved_at_utc) filter (
        where reservation.reserved_at_utc >
                candidate.proposed_at_utc
                - pg_catalog.make_interval(
                    hours => candidate.min_gap_hours
                  )
          and reservation.reserved_at_utc <
                candidate.proposed_at_utc
                + pg_catalog.make_interval(
                    hours => candidate.min_gap_hours
                  )
      )::integer as reservation_conflict_count,
      count(distinct (
        reservation.reservation_post_id,
        reservation.reserved_at_utc
      )) filter (
        where (
          reservation.reserved_at_utc at time zone candidate.timezone_name
        )::date = candidate.proposed_at_local::date
      )::integer as fixed_daily_reservation_count,
      count(distinct (
        reservation.reservation_post_id,
        reservation.reserved_at_utc
      )) filter (
        where pg_catalog.date_trunc(
          'week',
          reservation.reserved_at_utc at time zone candidate.timezone_name
        ) = pg_catalog.date_trunc('week', candidate.proposed_at_local)
      )::integer as fixed_weekly_reservation_count
    from candidate_basis candidate
    left join reservation_inventory reservation
      on reservation.buffer_channel_id = candidate.buffer_channel_id
     and reservation.reservation_post_id <> candidate.buffer_post_id
    group by
      candidate.buffer_post_id,
      candidate.slot_instance_key,
      candidate.proposed_at_utc,
      candidate.proposed_at_local,
      candidate.min_gap_hours,
      candidate.timezone_name
  ),

  candidate_scores as materialized (
    select
      candidate.*,
      reservation.reservation_conflict_count,
      reservation.fixed_daily_reservation_count,
      reservation.fixed_weekly_reservation_count,
      (
        case
          when candidate.content_day_matches
               and candidate.content_window_matches then 1000
          else 0
        end
        + case when candidate.content_day_matches then 260 else 0 end
        + case when candidate.content_window_matches then 220 else 0 end
        + greatest(
            0,
            120 - (candidate.content_day_distance * 30)
          )
        + greatest(
            0,
            80 - (candidate.content_hour_distance * 6)
          )
        + coalesce(candidate.platform_slot_recommendation_score, 0)
        - (coalesce(candidate.slot_rank, 99) * 0.10)
        - (candidate.cycle_slot_position * 0.01)
      )::numeric(12,2) as hybrid_assignment_score
    from candidate_basis candidate
    join candidate_reservation_state reservation
      on reservation.buffer_post_id = candidate.buffer_post_id
     and reservation.slot_instance_key = candidate.slot_instance_key
  ),

  safe_candidate_scores as materialized (
    select candidate.*
    from candidate_scores candidate
    where candidate.reservation_conflict_count = 0
      and candidate.fixed_daily_reservation_count + 1
            <= candidate.max_posts_per_day
      and candidate.fixed_weekly_reservation_count + 1
            <= candidate.posts_per_week
  ),

  ranked_candidate_options as materialized (
    select
      candidate.*,
      row_number() over (
        partition by candidate.buffer_post_id
        order by
          candidate.hybrid_assignment_score desc,
          candidate.source_recommendation_rank,
          candidate.slot_rank,
          candidate.slot_sequence
      )::integer as candidate_preference_rank
    from safe_candidate_scores candidate
  ),

  -- Parallel arrays preserve the exact existing candidate order while making
  -- each recursive step inspect only the current post's options.
  candidate_option_arrays as materialized (
    select
      candidate.buffer_post_id,
      array_agg(
        candidate.slot_instance_key
        order by candidate.candidate_preference_rank
      ) as slot_keys,
      array_agg(
        candidate.proposed_at_utc
        order by candidate.candidate_preference_rank
      ) as proposed_times,
      array_agg(
        candidate.fixed_daily_reservation_count
        order by candidate.candidate_preference_rank
      ) as fixed_daily_counts,
      array_agg(
        candidate.fixed_weekly_reservation_count
        order by candidate.candidate_preference_rank
      ) as fixed_weekly_counts
    from ranked_candidate_options candidate
    group by candidate.buffer_post_id
  ),

  assignments as (
    select
      post_record.buffer_channel_id,
      post_record.cadence_cycle,
      post_record.assignment_sequence,
      post_record.buffer_post_id,
      options.slot_keys[1] as slot_instance_key,
      case
        when options.slot_keys[1] is null then array[]::text[]
        else array[options.slot_keys[1]]::text[]
      end as used_slot_keys,
      case
        when options.proposed_times[1] is null then array[]::timestamptz[]
        else array[options.proposed_times[1]]::timestamptz[]
      end as used_slot_times
    from locked_ordered_posts post_record
    left join candidate_option_arrays options
      on options.buffer_post_id = post_record.buffer_post_id
    where post_record.assignment_sequence = 1

    union all

    select
      post_record.buffer_channel_id,
      post_record.cadence_cycle,
      post_record.assignment_sequence,
      post_record.buffer_post_id,
      case
        when chosen.candidate_index is null then null::text
        else options.slot_keys[chosen.candidate_index]
      end as slot_instance_key,
      case
        when chosen.candidate_index is null then assignment.used_slot_keys
        else pg_catalog.array_append(
          assignment.used_slot_keys,
          options.slot_keys[chosen.candidate_index]
        )
      end as used_slot_keys,
      case
        when chosen.candidate_index is null then assignment.used_slot_times
        else pg_catalog.array_append(
          assignment.used_slot_times,
          options.proposed_times[chosen.candidate_index]
        )
      end as used_slot_times
    from assignments assignment
    join locked_ordered_posts post_record
      on post_record.buffer_channel_id = assignment.buffer_channel_id
     and post_record.cadence_cycle = assignment.cadence_cycle
     and post_record.assignment_sequence =
           assignment.assignment_sequence + 1
    left join candidate_option_arrays options
      on options.buffer_post_id = post_record.buffer_post_id
    left join lateral (
      select option_index.candidate_index
      from pg_catalog.generate_subscripts(
        options.slot_keys,
        1
      ) option_index(candidate_index)
      where not (
        options.slot_keys[option_index.candidate_index] =
          any(assignment.used_slot_keys)
      )
        and not exists (
          select 1
          from pg_catalog.unnest(
            assignment.used_slot_times
          ) used(used_at_utc)
          where used.used_at_utc >
                  options.proposed_times[option_index.candidate_index]
                  - pg_catalog.make_interval(
                      hours => post_record.min_gap_hours
                    )
            and used.used_at_utc <
                  options.proposed_times[option_index.candidate_index]
                  + pg_catalog.make_interval(
                      hours => post_record.min_gap_hours
                    )
        )
        and options.fixed_daily_counts[option_index.candidate_index]
            + 1
            + (
              select count(*)::integer
              from pg_catalog.unnest(
                assignment.used_slot_times
              ) used(used_at_utc)
              where (
                used.used_at_utc at time zone post_record.timezone_name
              )::date = (
                options.proposed_times[option_index.candidate_index]
                  at time zone post_record.timezone_name
              )::date
            ) <= post_record.max_posts_per_day
        and options.fixed_weekly_counts[option_index.candidate_index]
            + 1
            + (
              select count(*)::integer
              from pg_catalog.unnest(
                assignment.used_slot_times
              ) used(used_at_utc)
              where pg_catalog.date_trunc(
                'week',
                used.used_at_utc at time zone post_record.timezone_name
              ) = pg_catalog.date_trunc(
                'week',
                options.proposed_times[option_index.candidate_index]
                  at time zone post_record.timezone_name
              )
            ) <= post_record.posts_per_week
      order by option_index.candidate_index
      limit 1
    ) chosen on true
  ),

  raw_assignments as materialized (
    select
      post_record.*,
      candidate.slot_instance_key,
      candidate.slot_sequence,
      candidate.cycle_slot_position,
      candidate.slot_rank,
      candidate.source_recommendation_rank,
      candidate.publish_iso_day,
      candidate.publish_day_name,
      candidate.scheduled_hour_local,
      candidate.scheduled_time_local,
      candidate.recommended_window,
      candidate.platform_slot_recommendation_score,
      candidate.platform_slot_confidence,
      candidate.platform_slot_supporting_sample_size,
      candidate.platform_slot_metrics_status,
      candidate.proposed_at_local,
      candidate.proposed_at_utc,
      candidate.content_day_matches,
      candidate.content_window_matches,
      candidate.content_day_distance,
      candidate.content_hour_distance,
      candidate.hybrid_assignment_score,
      candidate.reservation_conflict_count,
      candidate.fixed_daily_reservation_count,
      candidate.fixed_weekly_reservation_count
    from locked_ordered_posts post_record
    join assignments assignment
      on assignment.buffer_channel_id = post_record.buffer_channel_id
     and assignment.cadence_cycle = post_record.cadence_cycle
     and assignment.assignment_sequence = post_record.assignment_sequence
     and assignment.buffer_post_id = post_record.buffer_post_id
    left join ranked_candidate_options candidate
      on candidate.buffer_post_id = post_record.buffer_post_id
     and candidate.slot_instance_key = assignment.slot_instance_key
  ),

  guardrail_inputs as materialized (
    select
      assignment.*,
      count(*) filter (
        where assignment.proposed_at_local is not null
      ) over (
        partition by
          assignment.buffer_channel_id,
          assignment.proposed_at_local::date
      )::integer as new_batch_posts_that_day,
      count(*) filter (
        where assignment.proposed_at_local is not null
      ) over (
        partition by
          assignment.buffer_channel_id,
          pg_catalog.date_trunc('week', assignment.proposed_at_local)
      )::integer as new_batch_posts_that_week,
      pg_catalog.lag(assignment.proposed_at_utc) over (
        partition by assignment.buffer_channel_id
        order by
          assignment.proposed_at_utc nulls last,
          assignment.buffer_post_id
      ) as previous_proposed_at_utc
    from raw_assignments assignment
  ),

  ready_candidates as materialized (
    select
      assignment.buffer_post_id,
      assignment.platform,
      assignment.content_format,
      assignment.post_text,
      assignment.external_link,
      assignment.current_buffer_due_at_utc as current_due_at_utc,
      assignment.current_buffer_due_at_local as current_due_at_local,
      assignment.proposed_at_utc as proposed_due_at_utc,
      assignment.proposed_at_local as proposed_due_at_local,
      assignment.slot_rank,
      assignment.source_recommendation_rank,
      case
        when assignment.selected_model_level = 'Platform Overall' then
          coalesce(
            assignment.platform_slot_recommendation_score,
            assignment.platform_plan_score
          )
        else
          coalesce(
            assignment.content_recommendation_score,
            assignment.platform_slot_recommendation_score,
            assignment.platform_plan_score
          )
      end as recommendation_score,
      case
        when assignment.selected_model_level = 'Platform Overall' then
          coalesce(
            assignment.platform_slot_confidence,
            assignment.platform_plan_confidence
          )
        else
          coalesce(
            assignment.content_confidence,
            assignment.platform_slot_confidence,
            assignment.platform_plan_confidence
          )
      end as confidence,
      case
        when assignment.selected_model_level = 'Platform Overall' then
          coalesce(
            assignment.platform_slot_supporting_sample_size,
            assignment.platform_plan_supporting_sample_size,
            0
          )
        else
          coalesce(
            assignment.group_sample_size,
            assignment.platform_slot_supporting_sample_size,
            assignment.platform_plan_supporting_sample_size,
            0
          )
      end::integer as supporting_sample_size,
      case
        when assignment.selected_model_level = 'Platform Overall' then
          coalesce(
            assignment.platform_slot_metrics_status,
            assignment.platform_plan_metrics_status
          )
        else
          coalesce(
            assignment.content_metrics_status,
            assignment.platform_slot_metrics_status,
            assignment.platform_plan_metrics_status
          )
      end as metrics_status,
      assignment.timezone_name,
      assignment.buffer_channel_id,
      assignment.posts_per_week,
      assignment.max_posts_per_day,
      assignment.min_gap_hours,
      assignment.protected_hours,
      assignment.fixed_daily_reservation_count,
      assignment.fixed_weekly_reservation_count,
      row_number() over (
        partition by assignment.buffer_post_id
        order by
          assignment.proposed_at_utc,
          assignment.slot_instance_key
      ) as buffer_post_choice
    from guardrail_inputs assignment
    where assignment.proposed_at_utc is not null
      and assignment.labels_complete
      and assignment.recommendation_ready_for_preview
      and assignment.reservation_conflict_count = 0
      and assignment.fixed_daily_reservation_count + 1
            <= assignment.max_posts_per_day
      and assignment.fixed_weekly_reservation_count + 1
            <= assignment.posts_per_week
      and assignment.fixed_daily_reservation_count
          + assignment.new_batch_posts_that_day
            <= assignment.max_posts_per_day
      and assignment.fixed_weekly_reservation_count
          + assignment.new_batch_posts_that_week
            <= assignment.posts_per_week
      and (
        assignment.previous_proposed_at_utc is null
        or extract(epoch from (
          assignment.proposed_at_utc
          - assignment.previous_proposed_at_utc
        )) / 3600.0 >= assignment.min_gap_hours
      )
      and assignment.current_buffer_due_at_utc
            is distinct from assignment.proposed_at_utc
      and assignment.proposed_at_utc >
            pg_catalog.now()
            + pg_catalog.make_interval(hours => assignment.protected_hours)
      and (
        p_start_date is null
        or assignment.proposed_at_local::date >= p_start_date
      )
      and (
        p_end_date is null
        or assignment.proposed_at_local::date <= p_end_date
      )
      and not exists (
        select 1
        from public.schedule_change_proposals history
        where history.buffer_post_id = assignment.buffer_post_id
      )
  ),

  ranked as materialized (
    select
      candidate.*,
      row_number() over (
        order by
          candidate.platform,
          candidate.buffer_channel_id,
          candidate.proposed_due_at_utc,
          candidate.buffer_post_id
      ) as selection_order
    from ready_candidates candidate
    where candidate.buffer_post_choice = 1
  ),

  selected_preliminary as materialized (
    select ranked_candidate.*
    from ranked ranked_candidate
    order by ranked_candidate.selection_order
    limit p_limit
  ),

  -- Preserve migration-029 arbitrary-approval-subset semantics exactly: each
  -- candidate is evaluated against every earlier preliminary candidate,
  -- including one that a later predicate may itself reject.
  selected as materialized (
    select candidate.*
    from selected_preliminary candidate
    where not exists (
      select 1
      from selected_preliminary earlier
      where earlier.buffer_channel_id = candidate.buffer_channel_id
        and earlier.selection_order < candidate.selection_order
        and earlier.proposed_due_at_utc >
              candidate.proposed_due_at_utc
              - pg_catalog.make_interval(hours => greatest(
                  candidate.min_gap_hours,
                  earlier.min_gap_hours
                ))
        and earlier.proposed_due_at_utc <
              candidate.proposed_due_at_utc
              + pg_catalog.make_interval(hours => greatest(
                  candidate.min_gap_hours,
                  earlier.min_gap_hours
                ))
    )
      and candidate.fixed_daily_reservation_count
          + 1
          + (
            select count(*)::integer
            from selected_preliminary earlier
            where earlier.buffer_channel_id = candidate.buffer_channel_id
              and earlier.selection_order < candidate.selection_order
              and earlier.proposed_due_at_local::date =
                    candidate.proposed_due_at_local::date
          ) <= candidate.max_posts_per_day
      and candidate.fixed_weekly_reservation_count
          + 1
          + (
            select count(*)::integer
            from selected_preliminary earlier
            where earlier.buffer_channel_id = candidate.buffer_channel_id
              and earlier.selection_order < candidate.selection_order
              and pg_catalog.date_trunc(
                'week',
                earlier.proposed_due_at_local
              ) = pg_catalog.date_trunc(
                'week',
                candidate.proposed_due_at_local
              )
          ) <= candidate.posts_per_week
  ),

  inserted as (
    insert into public.schedule_change_proposals (
      buffer_post_id,
      platform,
      content_format,
      post_text,
      external_link,
      current_due_at_utc,
      current_due_at_local,
      proposed_due_at_utc,
      proposed_due_at_local,
      slot_rank,
      source_recommendation_rank,
      recommendation_score,
      confidence,
      supporting_sample_size,
      metrics_status,
      timezone_name,
      approval_status,
      approved_at,
      rejected_at,
      applied_at,
      result_message,
      error_message,
      generated_at,
      updated_at,
      sheet_exported_at
    )
    select
      candidate.buffer_post_id,
      candidate.platform,
      candidate.content_format,
      candidate.post_text,
      candidate.external_link,
      candidate.current_due_at_utc,
      candidate.current_due_at_local,
      candidate.proposed_due_at_utc,
      candidate.proposed_due_at_local,
      candidate.slot_rank,
      candidate.source_recommendation_rank,
      candidate.recommendation_score,
      candidate.confidence,
      candidate.supporting_sample_size,
      candidate.metrics_status,
      candidate.timezone_name,
      'Pending',
      null,
      null,
      null,
      null,
      null,
      pg_catalog.now(),
      pg_catalog.now(),
      null
    from selected candidate
    on conflict (buffer_post_id)
      where approval_status in ('Pending', 'Approved')
    do nothing
    returning buffer_post_id
  ),

  marked as (
    update public.posts post_record
    set schedule_evaluated_at = pg_catalog.now()
    from inserted proposal
    where post_record.buffer_post_id = proposal.buffer_post_id
      and post_record.schedule_evaluated_at is null
    returning post_record.buffer_post_id
  )

  select count(*)::integer
  into v_rows_created
  from inserted;

  return v_rows_created;
end;
$function$;

comment on function public.create_collision_safe_schedule_proposals(
  integer, date, date
) is
'Internal serialized range-aware proposal generator. It preserves migration-029 ordering and safeguards while sharing one set-based reservation inventory and avoiding the reporting-preview path.';

do $migration$
declare
  snapshot migration_032_generator_contract%rowtype;
  current_record pg_catalog.pg_proc%rowtype;
  view_contract text[];
begin
  select * into strict snapshot
  from migration_032_generator_contract;

  select * into strict current_record
  from pg_catalog.pg_proc
  where oid =
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure;

  if current_record.proowner is distinct from snapshot.proowner
     or current_record.proacl is distinct from snapshot.proacl
     or current_record.prosecdef is distinct from snapshot.prosecdef
     or current_record.proconfig is distinct from snapshot.proconfig
     or current_record.provolatile is distinct from snapshot.provolatile
     or current_record.prorettype is distinct from snapshot.prorettype
     or current_record.proargtypes is distinct from snapshot.proargtypes then
    raise exception
      'Migration 032 changed the generator owner, ACL, security, volatility, return type, or signature';
  end if;

  if not current_record.prosecdef
     or not (
       current_record.proconfig @> array['search_path=""']::text[]
     ) then
    raise exception
      'Migration 032 generator must remain SECURITY DEFINER with fixed empty search_path';
  end if;

  if position(
       'pg_advisory_xact_lock'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) = 0
     or position(
       'for update of post_record'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) = 0
     or position(
       'reservation_inventory as materialized'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) = 0
     or position(
       'looker_content_aware_proposal_preview'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) > 0
     or position(
       'find_schedule_slot_conflicts'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) > 0
     or position(
       'get_schedule_reservation_capacity'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) > 0
     or position(
       'calculate_schedule_reservation_state'
       in lower(pg_catalog.pg_get_functiondef(current_record.oid))
     ) > 0 then
    raise exception
      'Migration 032 generator lost its range-aware set-based implementation';
  end if;

  select array_agg(
    format(
      '%s:%s:%s',
      column_name,
      data_type,
      udt_name
    ) order by ordinal_position
  )
  into view_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if view_contract is distinct from array[
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
      'Migration 032 changed the 19-column Make-facing contract';
  end if;
end;
$migration$;

commit;
