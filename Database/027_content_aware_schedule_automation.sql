-- 027_content_aware_schedule_automation.sql
-- Switches the existing automated refresh RPC to the content-aware hybrid
-- proposal engine while preserving the existing Make.com RPC signature:
--   refresh_schedule_proposals(p_start_date date, p_horizon_days integer)
--
-- Safety preserved:
--   * manual approval remains required
--   * existing active Pending/Approved proposals are not replaced
--   * schedule_evaluated_at prevents repeated scheduling cycles
--   * p_start_date preserves the Make.com ~48-hour planning runway
--   * p_horizon_days preserves the 21-day planning horizon
--   * content-aware preview/guardrail checks must pass
--   * no-op schedule changes are skipped
--   * this function creates proposals only; it never edits Buffer directly

begin;

create or replace function public.refresh_schedule_proposals(
  p_start_date date default current_date,
  p_horizon_days integer default 21
)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_rows_changed integer := 0;
begin
  if p_horizon_days < 1 or p_horizon_days > 90 then
    raise exception 'p_horizon_days must be between 1 and 90';
  end if;

  if p_start_date is null then
    p_start_date := current_date;
  end if;

  with eligible as (
    select
      p.preview_key,
      p.buffer_post_id,
      p.platform,
      coalesce(p.content_format, 'short_form') as content_format,
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
      coalesce(p.timezone_name, 'America/Denver') as timezone_name,

      row_number() over (
        partition by p.buffer_post_id
        order by
          p.proposed_due_at_utc asc,
          p.preview_key asc
      ) as buffer_post_choice

    from public.looker_content_aware_proposal_preview p

    join public.posts bp
      on bp.buffer_post_id = p.buffer_post_id

    where bp.schedule_evaluated_at is null

      and p.ready_to_create = true
      and p.preview_status = 'Ready'
      and p.has_active_proposal = false
      and p.recommendation_ready_for_preview = true
      and p.shadow_ready_for_live_test = true
      and p.hybrid_guardrail_status = 'Pass'

      and p.current_due_at_utc is distinct from p.proposed_due_at_utc

      and p.proposed_due_at_local::date >= p_start_date

      and p.proposed_due_at_local::date
            <= (p_start_date + p_horizon_days)

      and p.proposed_due_at_utc >
            now() + make_interval(hours => coalesce(p.protected_hours, 24))
  ),

  selected as (
    select *
    from eligible
    where buffer_post_choice = 1
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
      s.buffer_post_id,
      s.platform,
      s.content_format,
      s.post_text,
      s.external_link,
      s.current_due_at_utc,
      s.current_due_at_local,
      s.proposed_due_at_utc,
      s.proposed_due_at_local,
      s.slot_rank,
      s.source_recommendation_rank,
      s.recommendation_score,
      s.confidence,
      s.supporting_sample_size,
      s.metrics_status,
      s.timezone_name,
      'Pending',
      null,
      null,
      null,
      null,
      null,
      now(),
      now(),
      null
    from selected s

    on conflict (buffer_post_id)
      where approval_status in ('Pending', 'Approved')
    do nothing

    returning buffer_post_id
  ),

  marked as (
    update public.posts bp
    set schedule_evaluated_at = now()
    from inserted i
    where bp.buffer_post_id = i.buffer_post_id
      and bp.schedule_evaluated_at is null
    returning bp.buffer_post_id
  )

  select count(*)::integer
  into v_rows_changed
  from inserted;

  return v_rows_changed;
end;
$function$;

revoke all on function public.refresh_schedule_proposals(date, integer)
  from public, anon, authenticated;

grant execute on function public.refresh_schedule_proposals(date, integer)
  to service_role;

comment on function public.refresh_schedule_proposals(date, integer) is
'Automated content-aware schedule proposal refresh. Uses the hybrid content-aware preview, preserves the existing Make RPC signature, start-date runway, horizon, manual approval gate, schedule-evaluation lock, active-proposal protection, and guardrails. Does not edit Buffer directly.';

commit;
