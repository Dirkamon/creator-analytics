-- Creator Analytics
-- Lock posts after their first schedule evaluation
-- File: Database/021_lock_evaluated_schedule_posts.sql
--
-- Purpose:
--   1. Each Buffer post is evaluated for scheduling only once.
--   2. Previously scheduled posts still occupy their position when
--      calculating slots for newly-added posts.
--   3. Posts that already match their recommended slot are also marked
--      evaluated, even though no proposal is created.
--   4. Existing Pending/Approved proposal safeguards remain intact.

begin;

alter table public.posts
  add column if not exists schedule_evaluated_at timestamptz;

comment on column public.posts.schedule_evaluated_at is
  'Timestamp when this Buffer post was first evaluated by the automated scheduling proposal system.';

-- Backfill posts that have already gone through the scheduling system.
-- This includes the currently Pending proposals generated this morning.
update public.posts p
set schedule_evaluated_at = existing.first_evaluated_at
from (
  select
    buffer_post_id,
    min(generated_at) as first_evaluated_at
  from public.schedule_change_proposals
  group by buffer_post_id
) existing
where p.buffer_post_id = existing.buffer_post_id
  and p.schedule_evaluated_at is null;


create or replace function public.refresh_schedule_proposals(
  p_start_date date default current_date,
  p_horizon_days integer default 21
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rows_changed integer := 0;
begin
  if p_horizon_days < 1 or p_horizon_days > 90 then
    raise exception 'p_horizon_days must be between 1 and 90';
  end if;

  with active_settings as (
    select
      platform,
      content_format,
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
      d.published_at_utc as current_due_at_utc,
      d.published_at_local as current_due_at_local,
      bp.schedule_evaluated_at,

      row_number() over (
        partition by d.platform
        order by
          d.published_at_utc asc,
          d.buffer_post_id asc
      ) as post_sequence

    from public.looker_dashboard_posts d

    join active_settings s
      on s.platform = d.platform

    join public.posts bp
      on bp.buffer_post_id = d.buffer_post_id

    where d.status = 'scheduled'
      and d.published_at_utc is not null
      and d.published_at_utc >
        now() + make_interval(hours => s.protected_hours)
  ),

  calendar_dates as (
    select
      generate_series(
        p_start_date::timestamp,
        (p_start_date + p_horizon_days)::timestamp,
        interval '1 day'
      )::date as local_date
  ),

  future_slots as (
    select
      w.platform,
      w.content_format,
      w.slot_rank,
      w.source_recommendation_rank,
      w.publish_iso_day,
      w.publish_day_name,
      w.scheduled_time_local,
      w.recommendation_score,
      w.confidence,
      w.supporting_sample_size,
      w.metrics_status,
      w.timezone_name,

      c.local_date + w.scheduled_time_local
        as proposed_due_at_local,

      (
        c.local_date + w.scheduled_time_local
      ) at time zone w.timezone_name
        as proposed_due_at_utc,

      row_number() over (
        partition by w.platform
        order by
          c.local_date asc,
          w.scheduled_time_local asc,
          w.slot_rank asc
      ) as slot_sequence

    from public.looker_weekly_slot_plan w

    join calendar_dates c
      on extract(isodow from c.local_date)::integer =
         w.publish_iso_day

    join active_settings s
      on s.platform = w.platform
     and s.content_format = w.content_format

    where (
      c.local_date + w.scheduled_time_local
    ) at time zone w.timezone_name >
      now() + make_interval(hours => s.protected_hours)
  ),

  paired as (
    select
      p.buffer_post_id,
      p.platform,
      p.content_format,
      p.post_text,
      p.external_link,
      p.current_due_at_utc,
      p.current_due_at_local,
      p.schedule_evaluated_at,

      s.proposed_due_at_utc,
      s.proposed_due_at_local,

      s.slot_rank,
      s.source_recommendation_rank,
      s.recommendation_score,
      s.confidence,
      s.supporting_sample_size,
      s.metrics_status,
      s.timezone_name

    from scheduled_posts p

    join future_slots s
      on s.platform = p.platform
     and s.slot_sequence = p.post_sequence
  ),

  upserted as (
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
      generated_at,
      updated_at
    )

    select
      p.buffer_post_id,
      p.platform,
      p.content_format,
      p.post_text,
      p.external_link,
      p.current_due_at_utc,
      p.current_due_at_local,
      p.proposed_due_at_utc,
      p.proposed_due_at_local,
      p.slot_rank,
      p.source_recommendation_rank,
      p.recommendation_score,
      p.confidence,
      p.supporting_sample_size,
      p.metrics_status,
      p.timezone_name,
      'Pending',
      now(),
      now()

    from paired p

    -- Only a post that has never been evaluated can receive
    -- a new scheduling proposal.
    where p.schedule_evaluated_at is null

      -- Preserve migration 020 no-op protection.
      and p.current_due_at_utc
        is distinct from p.proposed_due_at_utc

    on conflict (buffer_post_id)
      where approval_status in ('Pending', 'Approved')

    do update set
      platform = excluded.platform,
      content_format = excluded.content_format,
      post_text = excluded.post_text,
      external_link = excluded.external_link,
      current_due_at_utc = excluded.current_due_at_utc,
      current_due_at_local = excluded.current_due_at_local,
      proposed_due_at_utc = excluded.proposed_due_at_utc,
      proposed_due_at_local = excluded.proposed_due_at_local,
      slot_rank = excluded.slot_rank,

      source_recommendation_rank =
        excluded.source_recommendation_rank,

      recommendation_score =
        excluded.recommendation_score,

      confidence = excluded.confidence,

      supporting_sample_size =
        excluded.supporting_sample_size,

      metrics_status = excluded.metrics_status,
      timezone_name = excluded.timezone_name,
      generated_at = now(),
      updated_at = now(),

      approval_status = case
        when public.schedule_change_proposals.approval_status
          in ('Applied', 'Error')
        then public.schedule_change_proposals.approval_status
        else 'Pending'
      end,

      approved_at = case
        when public.schedule_change_proposals.approval_status
          in ('Applied', 'Error')
        then public.schedule_change_proposals.approved_at
        else null
      end,

      rejected_at = case
        when public.schedule_change_proposals.approval_status
          in ('Applied', 'Error')
        then public.schedule_change_proposals.rejected_at
        else null
      end

    -- Preserve migration 020 Approved-proposal freeze.
    where public.schedule_change_proposals.approval_status =
      'Pending'

    returning buffer_post_id
  ),

  -- Mark every newly-evaluated post, including posts where the
  -- current schedule already matched the recommendation.
  marked as (
    update public.posts bp
    set schedule_evaluated_at = now()

    from paired p

    where bp.buffer_post_id = p.buffer_post_id
      and bp.schedule_evaluated_at is null

    returning bp.buffer_post_id
  )

  select count(*)::integer
  into v_rows_changed
  from upserted;

  return v_rows_changed;
end;
$$;


revoke all on function public.refresh_schedule_proposals(date, integer)
  from public, anon, authenticated;

grant execute on function public.refresh_schedule_proposals(date, integer)
  to service_role;

commit;