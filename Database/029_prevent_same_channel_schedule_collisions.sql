-- Creator Analytics
-- Prevent same-channel scheduling collisions
-- File: Database/029_prevent_same_channel_schedule_collisions.sql
--
-- This migration keeps the existing manual approval and Make application
-- workflow. It adds fixed reservations for synchronized Buffer schedules and
-- active proposal targets, assigns only one-time/history-free candidates, and
-- revalidates the same-channel minimum gap both when proposals are generated
-- and immediately before they are exposed to Make.
--
-- Existing Looker, preview, summary, and Make-facing columns remain in their
-- original order and type. New diagnostic columns are appended only to the
-- Looker/preview views. No existing view is dropped.

begin;


-- Capture the pre-029 consumer contracts before any reporting view is
-- replaced. The end-of-migration assertion compares every preserved prefix by
-- ordinal position, column name, PostgreSQL type, and underlying UDT.
create temporary table migration_029_preserved_view_contracts
on commit drop
as
select
  c.table_name,
  c.ordinal_position,
  c.column_name,
  c.data_type,
  c.udt_schema,
  c.udt_name
from information_schema.columns c
join (
  values
    ('looker_content_aware_hybrid_shadow_schedule'::text, 75),
    ('looker_content_aware_hybrid_shadow_schedule_summary'::text, 13),
    ('looker_content_aware_proposal_preview'::text, 85),
    ('looker_content_aware_proposal_preview_summary'::text, 13),
    ('approved_schedule_changes_ready_to_apply'::text, 19)
) expected(table_name, preserved_column_count)
  on expected.table_name = c.table_name
 and c.ordinal_position <= expected.preserved_column_count
where c.table_schema = 'public';

do $$
declare
  v_missing_contract text;
begin
  with expected(table_name, preserved_column_count) as (
    values
      ('looker_content_aware_hybrid_shadow_schedule'::text, 75),
      ('looker_content_aware_hybrid_shadow_schedule_summary'::text, 13),
      ('looker_content_aware_proposal_preview'::text, 85),
      ('looker_content_aware_proposal_preview_summary'::text, 13),
      ('approved_schedule_changes_ready_to_apply'::text, 19)
  ),
  actual as (
    select
      table_name,
      count(*)::integer as column_count
    from migration_029_preserved_view_contracts
    group by table_name
  )
  select string_agg(
    format(
      '%s expected %s preserved columns but found %s',
      expected.table_name,
      expected.preserved_column_count,
      coalesce(actual.column_count, 0)
    ),
    '; '
  )
  into v_missing_contract
  from expected
  left join actual using (table_name)
  where coalesce(actual.column_count, 0)
        <> expected.preserved_column_count;

  if v_missing_contract is not null then
    raise exception
      'Migration 029 prerequisite reporting contract mismatch: %',
      v_missing_contract;
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- 1. Canonical schedule reservation inventory
-- ---------------------------------------------------------------------------

create or replace view public.schedule_slot_reservations
with (security_invoker = false)
as
select
  'Synchronized post schedule'::text as reservation_kind,
  p.buffer_post_id as reservation_post_id,
  null::uuid as reservation_proposal_id,
  p.buffer_channel_id,
  lower(trim(c.service))::text as platform,
  p.due_at as reserved_at_utc,
  p.status::text as source_status,
  p.last_synced_at as source_last_synced_at,
  null::timestamptz as source_applied_at
from public.posts p
join public.channels c
  on c.buffer_channel_id = p.buffer_channel_id
where p.status = 'scheduled'
  and p.due_at is not null

union all

select
  'Active proposal target'::text as reservation_kind,
  proposal.buffer_post_id as reservation_post_id,
  proposal.id as reservation_proposal_id,
  p.buffer_channel_id,
  lower(trim(c.service))::text as platform,
  proposal.proposed_due_at_utc as reserved_at_utc,
  proposal.approval_status::text as source_status,
  p.last_synced_at as source_last_synced_at,
  proposal.applied_at as source_applied_at
from public.schedule_change_proposals proposal
join public.posts p
  on p.buffer_post_id = proposal.buffer_post_id
join public.channels c
  on c.buffer_channel_id = p.buffer_channel_id
where proposal.approval_status in ('Pending', 'Approved')
  and proposal.proposed_due_at_utc is not null

union all

select
  'Applied target awaiting synchronization'::text as reservation_kind,
  proposal.buffer_post_id as reservation_post_id,
  proposal.id as reservation_proposal_id,
  p.buffer_channel_id,
  lower(trim(c.service))::text as platform,
  proposal.proposed_due_at_utc as reserved_at_utc,
  proposal.approval_status::text as source_status,
  p.last_synced_at as source_last_synced_at,
  proposal.applied_at as source_applied_at
from public.schedule_change_proposals proposal
join public.posts p
  on p.buffer_post_id = proposal.buffer_post_id
join public.channels c
  on c.buffer_channel_id = p.buffer_channel_id
where proposal.approval_status = 'Applied'
  and proposal.applied_at is not null
  and proposal.proposed_due_at_utc is not null
  and (
    p.last_synced_at is null
    or p.last_synced_at < proposal.applied_at
  );

comment on view public.schedule_slot_reservations is
'Service-only inventory of synchronized post times, Pending/Approved targets, and Applied targets that have not yet been superseded by a later post synchronization.';

revoke all on public.schedule_slot_reservations
from public, anon, authenticated;

grant select on public.schedule_slot_reservations
to service_role;


-- ---------------------------------------------------------------------------
-- 2. Authoritative interval-based same-channel conflict checker
-- ---------------------------------------------------------------------------

create or replace function public.find_schedule_slot_conflicts(
  p_candidate_post_id text,
  p_buffer_channel_id text,
  p_proposed_due_at_utc timestamptz,
  p_min_gap_hours integer,
  p_exclude_proposal_id uuid default null
)
returns table (
  reservation_kind text,
  reservation_post_id text,
  reservation_proposal_id uuid,
  buffer_channel_id text,
  platform text,
  reserved_at_utc timestamptz,
  source_status text,
  source_last_synced_at timestamptz,
  source_applied_at timestamptz,
  conflict_gap_hours numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if nullif(trim(p_candidate_post_id), '') is null then
    raise exception 'p_candidate_post_id is required';
  end if;

  if nullif(trim(p_buffer_channel_id), '') is null then
    raise exception 'p_buffer_channel_id is required';
  end if;

  if p_proposed_due_at_utc is null then
    raise exception 'p_proposed_due_at_utc is required';
  end if;

  if p_min_gap_hours is null or p_min_gap_hours <= 0 then
    raise exception 'p_min_gap_hours must be greater than zero';
  end if;

  return query
  select
    r.reservation_kind,
    r.reservation_post_id,
    r.reservation_proposal_id,
    r.buffer_channel_id,
    r.platform,
    r.reserved_at_utc,
    r.source_status,
    r.source_last_synced_at,
    r.source_applied_at,
    round(
      (
        abs(extract(epoch from (
          r.reserved_at_utc - p_proposed_due_at_utc
        ))) / 3600.0
      )::numeric,
      3
    ) as conflict_gap_hours
  from public.schedule_slot_reservations r
  where r.buffer_channel_id = p_buffer_channel_id
    -- Self-exclusion is by Buffer Post ID across every reservation kind.
    -- No reservation belonging to a different post is excluded.
    and r.reservation_post_id <> p_candidate_post_id
    and (
      p_exclude_proposal_id is null
      or r.reservation_proposal_id is distinct from p_exclude_proposal_id
    )
    -- Interval proximity is authoritative. Exact slot keys are not used here.
    and r.reserved_at_utc >
      p_proposed_due_at_utc
      - make_interval(hours => p_min_gap_hours)
    and r.reserved_at_utc <
      p_proposed_due_at_utc
      + make_interval(hours => p_min_gap_hours)
  order by
    r.reserved_at_utc,
    r.reservation_kind,
    r.reservation_post_id,
    r.reservation_proposal_id;
end;
$function$;

comment on function public.find_schedule_slot_conflicts(
  text, text, timestamptz, integer, uuid
) is
'Returns reservations inside the configured open minimum-gap interval on the same Buffer channel. Candidate self-exclusion uses Buffer Post ID across all reservation records.';

revoke all on function public.find_schedule_slot_conflicts(
  text, text, timestamptz, integer, uuid
)
from public, anon, authenticated;

grant execute on function public.find_schedule_slot_conflicts(
  text, text, timestamptz, integer, uuid
)
to service_role;


create or replace function public.get_schedule_reservation_capacity(
  p_candidate_post_id text,
  p_buffer_channel_id text,
  p_proposed_due_at_utc timestamptz,
  p_timezone_name text,
  p_exclude_proposal_id uuid default null
)
returns table (
  fixed_daily_reservation_count integer,
  fixed_weekly_reservation_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if nullif(trim(p_candidate_post_id), '') is null then
    raise exception 'p_candidate_post_id is required';
  end if;

  if nullif(trim(p_buffer_channel_id), '') is null then
    raise exception 'p_buffer_channel_id is required';
  end if;

  if p_proposed_due_at_utc is null then
    raise exception 'p_proposed_due_at_utc is required';
  end if;

  if nullif(trim(p_timezone_name), '') is null
     or not exists (
       select 1
       from pg_catalog.pg_timezone_names tz
       where tz.name = p_timezone_name
     ) then
    raise exception 'p_timezone_name is required and must be valid';
  end if;

  return query
  with distinct_fixed_reservations as (
    select distinct
      r.reservation_post_id,
      r.reserved_at_utc
    from public.schedule_slot_reservations r
    where r.buffer_channel_id = p_buffer_channel_id
      -- Only the candidate post is assumed to vacate its synchronized time.
      -- Every other post remains fixed so arbitrary approval subsets are safe.
      and r.reservation_post_id <> p_candidate_post_id
      and (
        p_exclude_proposal_id is null
        or r.reservation_proposal_id
             is distinct from p_exclude_proposal_id
      )
  ),
  target_period as (
    select
      (p_proposed_due_at_utc at time zone p_timezone_name)::date
        as target_local_date,
      date_trunc(
        'week',
        p_proposed_due_at_utc at time zone p_timezone_name
      ) as target_local_week
  )
  select
    count(*) filter (
      where (
        fixed.reserved_at_utc at time zone p_timezone_name
      )::date = period.target_local_date
    )::integer as fixed_daily_reservation_count,
    count(*) filter (
      where date_trunc(
        'week',
        fixed.reserved_at_utc at time zone p_timezone_name
      ) = period.target_local_week
    )::integer as fixed_weekly_reservation_count
  from distinct_fixed_reservations fixed
  cross join target_period period;
end;
$function$;

comment on function public.get_schedule_reservation_capacity(
  text, text, timestamptz, text, uuid
) is
'Counts distinct fixed reservation times on the candidate Buffer channel for the proposed local day and Monday-based local week. Only the candidate post reservations and optional own proposal are excluded.';

revoke all on function public.get_schedule_reservation_capacity(
  text, text, timestamptz, text, uuid
)
from public, anon, authenticated;

grant execute on function public.get_schedule_reservation_capacity(
  text, text, timestamptz, text, uuid
)
to service_role;

do $$
begin
  if exists (
    select 1 from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant execute on function public.find_schedule_slot_conflicts(
      text, text, timestamptz, integer, uuid
    ) to creator_dashboard_reader;

    grant execute on function public.get_schedule_reservation_capacity(
      text, text, timestamptz, text, uuid
    ) to creator_dashboard_reader;
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- 3. Collision-aware hybrid scheduler
--
-- The existing platform-wide recommendation source remains unchanged. Its
-- movable rows are regrouped by the actual Buffer channel, and actual post
-- schedules plus proposal targets are treated as fixed reservations.
-- ---------------------------------------------------------------------------

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
    exists (
      select 1
      from public.find_schedule_slot_conflicts(
        p.buffer_post_id,
        p.buffer_channel_id,
        f.proposed_at_utc,
        p.min_gap_hours,
        null
      ) conflict
    ) as has_reservation_conflict,
    capacity.fixed_daily_reservation_count,
    capacity.fixed_weekly_reservation_count,
    (
      capacity.fixed_daily_reservation_count + 1
      <= p.max_posts_per_day
    ) as has_fixed_daily_capacity,
    (
      capacity.fixed_weekly_reservation_count + 1
      <= p.posts_per_week
    ) as has_fixed_weekly_capacity
  from ordered_posts p
  join future_slots f
    on f.buffer_channel_id = p.buffer_channel_id
   and f.platform = p.platform
   and f.content_format = p.content_format
   and f.cadence_cycle = p.cadence_cycle
  cross join lateral public.get_schedule_reservation_capacity(
    p.buffer_post_id,
    p.buffer_channel_id,
    f.proposed_at_utc,
    p.timezone_name,
    null
  ) capacity
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


create or replace view
  public.looker_content_aware_hybrid_shadow_schedule_summary
with (security_invoker = false)
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
    where content_match_class = 'Exact content day + window'
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
  min(hybrid_proposed_at_local) as first_hybrid_slot_local,
  max(hybrid_proposed_at_local) as last_hybrid_slot_local,

  -- Appended migration-029 diagnostics.
  count(distinct buffer_channel_id)::integer as buffer_channels,
  sum(candidate_slot_count)::bigint as candidate_slots_considered,
  sum(excluded_collision_slot_count)::bigint as slots_excluded_by_reservations,
  count(*) filter (
    where collision_free_slot_count = 0
  )::integer as posts_blocked_by_reservations,
  count(*) filter (
    where collision_free_slot_count > 0
      and capacity_safe_slot_count = 0
  )::integer as posts_blocked_by_fixed_capacity,
  sum(excluded_daily_capacity_slot_count)::bigint
    as slots_excluded_by_daily_capacity,
  sum(excluded_weekly_capacity_slot_count)::bigint
    as slots_excluded_by_weekly_capacity
from public.looker_content_aware_hybrid_shadow_schedule
group by platform;

comment on view public.looker_content_aware_hybrid_shadow_schedule is
'Channel-aware hybrid scheduler for one-time/history-free movable posts. Actual synchronized post times and active/unsynchronized Applied targets are fixed reservations; configured interval gaps are authoritative.';

comment on view public.looker_content_aware_hybrid_shadow_schedule_summary is
'Existing hybrid scheduler summary with appended same-channel reservation diagnostics.';

revoke all on public.looker_content_aware_hybrid_shadow_schedule
from public, anon, authenticated;

revoke all on public.looker_content_aware_hybrid_shadow_schedule_summary
from public, anon, authenticated;

grant select on public.looker_content_aware_hybrid_shadow_schedule
to service_role;

grant select on public.looker_content_aware_hybrid_shadow_schedule_summary
to service_role;

do $$
begin
  if exists (
    select 1 from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant select on public.looker_content_aware_hybrid_shadow_schedule
    to creator_dashboard_reader;

    grant select on
      public.looker_content_aware_hybrid_shadow_schedule_summary
    to creator_dashboard_reader;
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- 5. Application-time diagnostic preflight and unchanged Make contract
-- ---------------------------------------------------------------------------

create or replace view public.schedule_change_application_preflight
with (security_invoker = false)
as
with inspected as (
  select
    proposal.id as proposal_id,
    proposal.buffer_post_id,
    proposal.platform,
    proposal.content_format,
    proposal.post_text,
    proposal.external_link,
    proposal.current_due_at_utc,
    proposal.current_due_at_local,
    proposal.proposed_due_at_utc,
    proposal.proposed_due_at_local,
    proposal.slot_rank,
    proposal.source_recommendation_rank,
    proposal.recommendation_score,
    proposal.confidence,
    proposal.supporting_sample_size,
    proposal.metrics_status,
    proposal.timezone_name,
    proposal.approval_status,
    proposal.approved_at,
    proposal.applied_at,
    proposal.error_message,
    p.buffer_channel_id,
    p.status as current_post_status,
    p.due_at as synchronized_due_at_utc,
    p.last_synced_at as post_last_synced_at,
    c.service as channel_service,
    settings.is_active as cadence_is_active,
    settings.posts_per_week,
    settings.max_posts_per_day,
    settings.min_gap_hours,
    settings.protected_hours,
    settings.timezone_name as configured_timezone_name,
    (
      p.buffer_post_id is not null
    ) as post_exists,
    (
      nullif(trim(p.buffer_channel_id), '') is not null
      and c.buffer_channel_id is not null
      and nullif(trim(c.service), '') is not null
      and lower(trim(c.service)) = lower(trim(proposal.platform))
    ) as channel_identity_valid,
    (
      settings.platform is not null
      and settings.is_active = true
      and settings.posts_per_week > 0
      and settings.max_posts_per_day > 0
    ) as cadence_configuration_valid,
    (
      settings.min_gap_hours is not null
      and settings.min_gap_hours > 0
    ) as minimum_gap_configuration_valid,
    (
      settings.protected_hours is not null
      and settings.protected_hours >= 0
    ) as protected_hours_configuration_valid,
    (
      nullif(trim(settings.timezone_name), '') is not null
      and exists (
        select 1
        from pg_catalog.pg_timezone_names tz
        where tz.name = settings.timezone_name
      )
    ) as timezone_configuration_valid,
    case
      when nullif(trim(p.buffer_channel_id), '') is null
        or settings.min_gap_hours is null
        or settings.min_gap_hours <= 0
        or proposal.proposed_due_at_utc is null
      then null::integer
      else (
        select count(*)::integer
        from public.find_schedule_slot_conflicts(
          proposal.buffer_post_id,
          p.buffer_channel_id,
          proposal.proposed_due_at_utc,
          settings.min_gap_hours,
          proposal.id
        ) conflict
      )
    end as reservation_conflict_count,
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
        or proposal.proposed_due_at_utc is null
      then null::integer
      else (
        select capacity.fixed_daily_reservation_count
        from public.get_schedule_reservation_capacity(
          proposal.buffer_post_id,
          p.buffer_channel_id,
          proposal.proposed_due_at_utc,
          settings.timezone_name,
          proposal.id
        ) capacity
      )
    end as fixed_daily_reservation_count,
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
        or proposal.proposed_due_at_utc is null
      then null::integer
      else (
        select capacity.fixed_weekly_reservation_count
        from public.get_schedule_reservation_capacity(
          proposal.buffer_post_id,
          p.buffer_channel_id,
          proposal.proposed_due_at_utc,
          settings.timezone_name,
          proposal.id
        ) capacity
      )
    end as fixed_weekly_reservation_count
  from public.schedule_change_proposals proposal
  left join public.posts p
    on p.buffer_post_id = proposal.buffer_post_id
  left join public.channels c
    on c.buffer_channel_id = p.buffer_channel_id
  left join public.scheduling_cadence_settings settings
    on settings.platform = proposal.platform
   and settings.content_format = proposal.content_format
  where proposal.approval_status = 'Approved'
    and proposal.applied_at is null
    and proposal.error_message is null
),

reasoned as (
  select
    i.*,
    array_remove(array[
      case
        when not i.post_exists then
          'Blocked: Buffer post is missing from synchronized posts'
      end,
      case
        when i.post_exists
             and i.current_post_status is distinct from 'scheduled' then
          'Blocked: post is no longer scheduled'
      end,
      case
        when not coalesce(i.channel_identity_valid, false) then
          'Blocked: Buffer channel identity is missing or does not match platform'
      end,
      case
        when not coalesce(i.cadence_configuration_valid, false) then
          'Blocked: active cadence configuration is missing or invalid'
      end,
      case
        when not coalesce(i.minimum_gap_configuration_valid, false) then
          'Blocked: minimum-gap configuration is missing or invalid'
      end,
      case
        when not coalesce(i.protected_hours_configuration_valid, false) then
          'Blocked: protected-hours configuration is missing or invalid'
      end,
      case
        when not coalesce(i.timezone_configuration_valid, false) then
          'Blocked: timezone configuration is missing or invalid'
      end,
      case
        when i.current_due_at_utc is null then
          'Blocked: proposal did not capture a current schedule time'
      end,
      case
        when i.synchronized_due_at_utc is null then
          'Blocked: synchronized current schedule time is missing'
      end,
      case
        when i.current_due_at_utc is not null
         and i.synchronized_due_at_utc is not null
         and i.synchronized_due_at_utc <> i.current_due_at_utc then
          'Blocked: current schedule changed after proposal generation'
      end,
      case
        when coalesce(i.protected_hours_configuration_valid, false)
         and i.proposed_due_at_utc <=
             now() + make_interval(hours => i.protected_hours) then
          'Blocked: proposed time is inside the protected scheduling window'
      end,
      case
        when coalesce(i.reservation_conflict_count, 0) > 0 then
          'Blocked: proposed time violates the configured same-channel minimum gap'
      end,
      case
        when i.fixed_daily_reservation_count is not null
         and i.max_posts_per_day is not null
         and i.fixed_daily_reservation_count + 1
             > i.max_posts_per_day then
          'Blocked: fixed reservations plus this target exceed daily channel capacity'
      end,
      case
        when i.fixed_weekly_reservation_count is not null
         and i.posts_per_week is not null
         and i.fixed_weekly_reservation_count + 1
             > i.posts_per_week then
          'Blocked: fixed reservations plus this target exceed weekly channel capacity'
      end
    ]::text[], null) as blocking_reasons
  from inspected i
),

finalized_preflight as (
  select
    r.*,
    coalesce(cardinality(r.blocking_reasons), 0) = 0 as is_ready,
    r.blocking_reasons[1] as blocking_reason
  from reasoned r
)

select
  proposal_id,
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
  buffer_channel_id,
  current_post_status,
  synchronized_due_at_utc,
  post_last_synced_at,
  channel_service,
  cadence_is_active,
  posts_per_week,
  max_posts_per_day,
  min_gap_hours,
  protected_hours,
  configured_timezone_name,
  post_exists,
  channel_identity_valid,
  cadence_configuration_valid,
  minimum_gap_configuration_valid,
  protected_hours_configuration_valid,
  timezone_configuration_valid,
  reservation_conflict_count,
  fixed_daily_reservation_count,
  fixed_weekly_reservation_count,
  case
    when fixed_daily_reservation_count is null then null::integer
    else fixed_daily_reservation_count + 1
  end as projected_daily_post_count,
  case
    when fixed_weekly_reservation_count is null then null::integer
    else fixed_weekly_reservation_count + 1
  end as projected_weekly_post_count,
  blocking_reasons,
  blocking_reason,
  is_ready
from finalized_preflight;

comment on view public.schedule_change_application_preflight is
'Service-only diagnostic preflight for Approved changes. It fails closed on stale current schedules, invalid identity/configuration, protected-window entry, same-channel interval collisions, and fixed-plus-target daily or weekly capacity.';

revoke all on public.schedule_change_application_preflight
from public, anon, authenticated;

grant select on public.schedule_change_application_preflight
to service_role;


-- The first nineteen columns, their order, and their types exactly preserve
-- migration 018's Make-facing schema. Diagnostics remain in the separate
-- preflight view so existing Make reads require no mapping changes.
create or replace view public.approved_schedule_changes_ready_to_apply
with (security_invoker = false)
as
select
  preflight.proposal_id,
  preflight.buffer_post_id,
  preflight.platform,
  preflight.content_format,
  preflight.post_text,
  preflight.external_link,
  preflight.current_due_at_utc,
  preflight.current_due_at_local,
  preflight.proposed_due_at_utc,
  preflight.proposed_due_at_local,
  preflight.slot_rank,
  preflight.source_recommendation_rank,
  preflight.recommendation_score,
  preflight.confidence,
  preflight.supporting_sample_size,
  preflight.metrics_status,
  preflight.timezone_name,
  preflight.approval_status,
  preflight.approved_at
from public.schedule_change_application_preflight preflight
where preflight.is_ready
order by
  preflight.proposed_due_at_utc,
  preflight.platform;

comment on view public.approved_schedule_changes_ready_to_apply is
'Migration-018-compatible Make feed, now restricted to Approved proposals that pass current-schedule, configuration, protected-window, same-channel minimum-gap, daily-capacity, and weekly-capacity preflight checks.';

revoke all on public.approved_schedule_changes_ready_to_apply
from public, anon, authenticated;

grant select on public.approved_schedule_changes_ready_to_apply
to service_role;


-- ---------------------------------------------------------------------------
-- 4. Proposal preview with current reservation/configuration diagnostics
-- ---------------------------------------------------------------------------

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
      else (
        select count(*)::integer
        from public.find_schedule_slot_conflicts(
          h.buffer_post_id,
          p.buffer_channel_id,
          h.hybrid_proposed_at_utc,
          settings.min_gap_hours,
          null
        ) conflict
      )
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
      else (
        select capacity.fixed_daily_reservation_count
        from public.get_schedule_reservation_capacity(
          h.buffer_post_id,
          p.buffer_channel_id,
          h.hybrid_proposed_at_utc,
          settings.timezone_name,
          null
        ) capacity
      )
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
      else (
        select capacity.fixed_weekly_reservation_count
        from public.get_schedule_reservation_capacity(
          h.buffer_post_id,
          p.buffer_channel_id,
          h.hybrid_proposed_at_utc,
          settings.timezone_name,
          null
        ) capacity
      )
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


create or replace view public.looker_content_aware_proposal_preview_summary
with (security_invoker = false)
as
select
  platform,
  count(*)::integer as preview_rows,
  count(*) filter (where ready_to_create)::integer as ready_to_create,
  count(*) filter (where not ready_to_create)::integer as blocked_rows,
  count(*) filter (where has_active_proposal)::integer
    as blocked_by_active_proposal,
  count(*) filter (
    where selected_model_level <> 'Platform Overall'
  )::integer as content_specific_rows,
  count(*) filter (
    where selected_model_level = 'Platform Overall'
  )::integer as platform_overall_fallback_rows,
  count(*) filter (
    where content_day_matches and content_window_matches
  )::integer as exact_content_day_and_window_rows,
  count(*) filter (
    where exact_platform_plan_match
  )::integer as unchanged_from_platform_plan_rows,
  count(*) filter (
    where not exact_platform_plan_match
  )::integer as reassigned_inside_cadence_cycle_rows,
  count(*) filter (
    where hybrid_guardrail_status = 'Pass'
  )::integer as guardrail_pass_rows,
  min(proposed_due_at_local) as first_proposed_at_local,
  max(proposed_due_at_local) as last_proposed_at_local,

  -- Appended migration-029 diagnostics.
  count(*) filter (
    where coalesce(current_reservation_conflict_count, 0) > 0
  )::integer as blocked_by_same_channel_reservation,
  count(*) filter (
    where not coalesce(channel_identity_valid, false)
  )::integer as blocked_by_channel_identity,
  count(*) filter (
    where not coalesce(cadence_configuration_valid, false)
  )::integer as blocked_by_configuration,
  count(*) filter (
    where current_fixed_daily_reservation_count + 1
          > max_posts_per_day
  )::integer as blocked_by_daily_capacity,
  count(*) filter (
    where current_fixed_weekly_reservation_count + 1
          > configured_posts_per_week
  )::integer as blocked_by_weekly_capacity
from public.looker_content_aware_proposal_preview
group by platform;

comment on view public.looker_content_aware_proposal_preview is
'Existing proposal-shaped preview contract with appended channel/configuration/collision/capacity diagnostics and current reservation revalidation.';

comment on view public.looker_content_aware_proposal_preview_summary is
'Existing proposal preview summary with appended same-channel and configuration block totals.';

revoke all on public.looker_content_aware_proposal_preview
from public, anon, authenticated;

revoke all on public.looker_content_aware_proposal_preview_summary
from public, anon, authenticated;

grant select on public.looker_content_aware_proposal_preview
to service_role;

grant select on public.looker_content_aware_proposal_preview_summary
to service_role;

do $$
begin
  if exists (
    select 1 from pg_roles
    where rolname = 'creator_dashboard_reader'
  ) then
    grant select on public.looker_content_aware_proposal_preview
    to creator_dashboard_reader;

    grant select on public.looker_content_aware_proposal_preview_summary
    to creator_dashboard_reader;
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- 6. Serialized, collision-safe proposal generation
-- ---------------------------------------------------------------------------

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

  -- Both public generation entry points share this transaction-scoped lock.
  -- It serializes proposal batches without changing approval behavior.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'creator-analytics-schedule-proposal-generation',
      0
    )
  );

  with locked_posts as materialized (
    select post_record.*
    from public.posts post_record
    where post_record.status = 'scheduled'
      and post_record.due_at is not null
      and post_record.schedule_evaluated_at is null
      and not exists (
        select 1
        from public.schedule_change_proposals history
        where history.buffer_post_id = post_record.buffer_post_id
      )
    for update
  ),

  eligible as materialized (
    select
      preview.preview_key,
      preview.buffer_post_id,
      preview.platform,
      preview.content_format,
      preview.post_text,
      preview.external_link,
      preview.current_due_at_utc,
      preview.current_due_at_local,
      preview.proposed_due_at_utc,
      preview.proposed_due_at_local,
      preview.slot_rank,
      preview.source_recommendation_rank,
      preview.recommendation_score,
      preview.confidence,
      preview.supporting_sample_size,
      preview.metrics_status,
      preview.timezone_name,
      post_record.buffer_channel_id,
      settings.posts_per_week,
      settings.max_posts_per_day,
      settings.min_gap_hours,
      settings.protected_hours,
      capacity.fixed_daily_reservation_count,
      capacity.fixed_weekly_reservation_count,
      row_number() over (
        partition by preview.buffer_post_id
        order by
          preview.proposed_due_at_utc,
          preview.preview_key
      ) as buffer_post_choice
    from public.looker_content_aware_proposal_preview preview
    join locked_posts post_record
      on post_record.buffer_post_id = preview.buffer_post_id
    join public.channels channel_record
      on channel_record.buffer_channel_id = post_record.buffer_channel_id
    join public.scheduling_cadence_settings settings
      on settings.platform = preview.platform
     and settings.content_format = preview.content_format
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
    cross join lateral public.get_schedule_reservation_capacity(
      preview.buffer_post_id,
      post_record.buffer_channel_id,
      preview.proposed_due_at_utc,
      settings.timezone_name,
      null
    ) capacity
    where preview.ready_to_create = true
      and preview.preview_status = 'Ready'
      and preview.has_active_proposal = false
      and preview.recommendation_ready_for_preview = true
      and preview.shadow_ready_for_live_test = true
      and preview.hybrid_guardrail_status = 'Pass'
      and post_record.schedule_evaluated_at is null
      and post_record.status = 'scheduled'
      -- A stale preview is never converted into a proposal.
      and post_record.due_at = preview.current_due_at_utc
      and preview.current_due_at_utc
            is distinct from preview.proposed_due_at_utc
      and nullif(trim(post_record.buffer_channel_id), '') is not null
      and nullif(trim(channel_record.service), '') is not null
      and lower(trim(channel_record.service)) = lower(trim(preview.platform))
      and preview.timezone_name = settings.timezone_name
      and preview.proposed_due_at_utc >
            now() + make_interval(hours => settings.protected_hours)
      and (
        p_start_date is null
        or preview.proposed_due_at_local::date >= p_start_date
      )
      and (
        p_end_date is null
        or preview.proposed_due_at_local::date <= p_end_date
      )
      and not exists (
        select 1
        from public.schedule_change_proposals history
        where history.buffer_post_id = preview.buffer_post_id
      )
      and not exists (
        select 1
        from public.find_schedule_slot_conflicts(
          preview.buffer_post_id,
          post_record.buffer_channel_id,
          preview.proposed_due_at_utc,
          settings.min_gap_hours,
          null
        ) conflict
      )
      and capacity.fixed_daily_reservation_count + 1
            <= settings.max_posts_per_day
      and capacity.fixed_weekly_reservation_count + 1
            <= settings.posts_per_week
  ),

  ranked as (
    select
      e.*,
      row_number() over (
        order by
          e.platform,
          e.buffer_channel_id,
          e.proposed_due_at_utc,
          e.buffer_post_id
      ) as selection_order
    from eligible e
    where e.buffer_post_choice = 1
  ),

  selected_preliminary as materialized (
    select *
    from ranked
    order by selection_order
    limit p_limit
  ),

  -- Defense in depth against arbitrary approval subsets and a future preview
  -- regression: every retained target must also be interval-safe relative to
  -- every earlier retained target in this proposed batch.
  selected as (
    select candidate.*
    from selected_preliminary candidate
    where not exists (
      select 1
      from selected_preliminary earlier
      where earlier.buffer_channel_id = candidate.buffer_channel_id
        and earlier.selection_order < candidate.selection_order
        and earlier.proposed_due_at_utc >
              candidate.proposed_due_at_utc
              - make_interval(hours => greatest(
                  candidate.min_gap_hours,
                  earlier.min_gap_hours
                ))
        and earlier.proposed_due_at_utc <
              candidate.proposed_due_at_utc
              + make_interval(hours => greatest(
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
              and date_trunc('week', earlier.proposed_due_at_local) =
                    date_trunc('week', candidate.proposed_due_at_local)
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
      selected_post.buffer_post_id,
      selected_post.platform,
      selected_post.content_format,
      selected_post.post_text,
      selected_post.external_link,
      selected_post.current_due_at_utc,
      selected_post.current_due_at_local,
      selected_post.proposed_due_at_utc,
      selected_post.proposed_due_at_local,
      selected_post.slot_rank,
      selected_post.source_recommendation_rank,
      selected_post.recommendation_score,
      selected_post.confidence,
      selected_post.supporting_sample_size,
      selected_post.metrics_status,
      selected_post.timezone_name,
      'Pending',
      null,
      null,
      null,
      null,
      null,
      now(),
      now(),
      null
    from selected selected_post
    on conflict (buffer_post_id)
      where approval_status in ('Pending', 'Approved')
    do nothing
    returning buffer_post_id
  ),

  marked as (
    update public.posts post_record
    set schedule_evaluated_at = now()
    from inserted new_proposal
    where post_record.buffer_post_id = new_proposal.buffer_post_id
      and post_record.schedule_evaluated_at is null
    returning post_record.buffer_post_id
  )

  select count(*)::integer
  into v_rows_created
  from inserted;

  return v_rows_created;
end;
$function$;

revoke all on function public.create_collision_safe_schedule_proposals(
  integer, date, date
)
from public, anon, authenticated;

comment on function public.create_collision_safe_schedule_proposals(
  integer, date, date
) is
'Internal serialized proposal generator. Locks candidate posts, rechecks one-time/history/configuration/current-time/protected-window/reservation invariants, and rejects interval-conflicting or daily/weekly over-capacity batch targets.';


create or replace function public.create_content_aware_schedule_proposals(
  p_limit integer default 50
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_limit < 1 or p_limit > 500 then
    raise exception 'p_limit must be between 1 and 500';
  end if;

  return public.create_collision_safe_schedule_proposals(
    p_limit,
    null,
    null
  );
end;
$function$;

revoke all on function public.create_content_aware_schedule_proposals(integer)
from public, anon, authenticated;

grant execute on function public.create_content_aware_schedule_proposals(integer)
to service_role;

comment on function public.create_content_aware_schedule_proposals(integer) is
'Creates one-time Pending content-aware proposals after serialized current-schedule, configuration, protected-window, same-channel interval, and daily/weekly capacity revalidation. Manual approval remains mandatory.';


create or replace function public.refresh_schedule_proposals(
  p_start_date date default current_date,
  p_horizon_days integer default 21
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_horizon_days < 1 or p_horizon_days > 90 then
    raise exception 'p_horizon_days must be between 1 and 90';
  end if;

  if p_start_date is null then
    p_start_date := current_date;
  end if;

  return public.create_collision_safe_schedule_proposals(
    null,
    p_start_date,
    p_start_date + p_horizon_days
  );
end;
$function$;

revoke all on function public.refresh_schedule_proposals(date, integer)
from public, anon, authenticated;

grant execute on function public.refresh_schedule_proposals(date, integer)
to service_role;

comment on function public.refresh_schedule_proposals(date, integer) is
'Automated one-time content-aware refresh with the existing start-date/horizon contract plus serialized current-schedule, configuration, protected-window, same-channel interval, and daily/weekly capacity revalidation. It never edits Buffer.';


-- Fail the transaction if any pre-029 reporting/Make column prefix changed
-- name, ordinal position, information_schema type, or underlying UDT.
do $$
declare
  v_contract_mismatch text;
begin
  with current_contract as (
    select
      c.table_name,
      c.ordinal_position,
      c.column_name,
      c.data_type,
      c.udt_schema,
      c.udt_name
    from information_schema.columns c
    join (
      values
        ('looker_content_aware_hybrid_shadow_schedule'::text, 75),
        ('looker_content_aware_hybrid_shadow_schedule_summary'::text, 13),
        ('looker_content_aware_proposal_preview'::text, 85),
        ('looker_content_aware_proposal_preview_summary'::text, 13),
        ('approved_schedule_changes_ready_to_apply'::text, 19)
    ) expected(table_name, preserved_column_count)
      on expected.table_name = c.table_name
     and c.ordinal_position <= expected.preserved_column_count
    where c.table_schema = 'public'
  ),
  differences as (
    select
      coalesce(before.table_name, after.table_name) as table_name,
      coalesce(before.ordinal_position, after.ordinal_position)
        as ordinal_position,
      before.column_name as before_column_name,
      after.column_name as after_column_name,
      before.data_type as before_data_type,
      after.data_type as after_data_type,
      before.udt_schema as before_udt_schema,
      after.udt_schema as after_udt_schema,
      before.udt_name as before_udt_name,
      after.udt_name as after_udt_name
    from migration_029_preserved_view_contracts before
    full join current_contract after
      on after.table_name = before.table_name
     and after.ordinal_position = before.ordinal_position
    where before.column_name is distinct from after.column_name
       or before.data_type is distinct from after.data_type
       or before.udt_schema is distinct from after.udt_schema
       or before.udt_name is distinct from after.udt_name
  )
  select string_agg(
    format(
      '%s[%s] %s (%s.%s) -> %s (%s.%s)',
      table_name,
      ordinal_position,
      coalesce(before_column_name, '(missing)'),
      coalesce(before_udt_schema, '?'),
      coalesce(before_udt_name, before_data_type, '?'),
      coalesce(after_column_name, '(missing)'),
      coalesce(after_udt_schema, '?'),
      coalesce(after_udt_name, after_data_type, '?')
    ),
    '; '
    order by table_name, ordinal_position
  )
  into v_contract_mismatch
  from differences;

  if v_contract_mismatch is not null then
    raise exception
      'Migration 029 reporting contract changed; transaction will roll back: %',
      v_contract_mismatch;
  end if;
end;
$$;


commit;
