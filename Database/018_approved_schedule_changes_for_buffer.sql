-- Creator Analytics
-- Approved schedule changes ready for Buffer + application tracking
-- File: Database/018_approved_schedule_changes_for_buffer.sql
--
-- Creates:
--   1. A service-only view of approved proposals that are safe to apply.
--   2. RPC to mark a proposal Applied after Buffer confirms success.
--   3. RPC to mark a proposal Error if the Buffer update fails.
--
-- This migration does NOT call Buffer and does NOT change any post schedule.
-- Safe to rerun.

begin;

create or replace view public.approved_schedule_changes_ready_to_apply
with (security_invoker = false)
as
select
  p.id as proposal_id,
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
  p.approval_status,
  p.approved_at
from public.schedule_change_proposals p
join public.looker_dashboard_posts d
  on d.buffer_post_id = p.buffer_post_id
join public.scheduling_cadence_settings s
  on s.platform = p.platform
 and s.content_format = p.content_format
where p.approval_status = 'Approved'
  and p.applied_at is null
  and p.error_message is null
  and d.status = 'scheduled'
  and p.proposed_due_at_utc >
      now() + make_interval(hours => s.protected_hours)
order by
  p.proposed_due_at_utc asc,
  p.platform asc;

create or replace function public.mark_schedule_proposal_applied(
  p_proposal_id uuid,
  p_result_message text default 'Buffer schedule updated successfully'
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.schedule_change_proposals
  set
    approval_status = 'Applied',
    applied_at = now(),
    result_message = coalesce(
      nullif(trim(p_result_message), ''),
      'Buffer schedule updated successfully'
    ),
    error_message = null,
    updated_at = now()
  where id = p_proposal_id
    and approval_status = 'Approved'
    and applied_at is null;

  return found;
end;
$$;

create or replace function public.mark_schedule_proposal_error(
  p_proposal_id uuid,
  p_error_message text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.schedule_change_proposals
  set
    approval_status = 'Error',
    error_message = nullif(trim(p_error_message), ''),
    result_message = null,
    updated_at = now()
  where id = p_proposal_id
    and approval_status = 'Approved'
    and applied_at is null;

  return found;
end;
$$;

revoke all on public.approved_schedule_changes_ready_to_apply
  from public, anon, authenticated;

revoke all on function public.mark_schedule_proposal_applied(uuid, text)
  from public, anon, authenticated;

revoke all on function public.mark_schedule_proposal_error(uuid, text)
  from public, anon, authenticated;

grant select on public.approved_schedule_changes_ready_to_apply
  to service_role;

grant execute on function public.mark_schedule_proposal_applied(uuid, text)
  to service_role;

grant execute on function public.mark_schedule_proposal_error(uuid, text)
  to service_role;

commit;
