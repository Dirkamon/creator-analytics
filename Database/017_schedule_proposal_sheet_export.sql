-- Creator Analytics
-- Schedule proposal export tracking for Google Sheets
-- File: Database/017_schedule_proposal_sheet_export.sql
--
-- Adds export tracking so Make can send each pending proposal to Google Sheets
-- once without creating duplicate rows.
--
-- This migration does NOT change anything in Buffer.
-- Safe to rerun.

begin;

alter table public.schedule_change_proposals
  add column if not exists sheet_exported_at timestamptz;

create or replace function public.reset_schedule_proposal_sheet_export()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.current_due_at_utc is distinct from new.current_due_at_utc
     or old.current_due_at_local is distinct from new.current_due_at_local
     or old.proposed_due_at_utc is distinct from new.proposed_due_at_utc
     or old.proposed_due_at_local is distinct from new.proposed_due_at_local
     or old.post_text is distinct from new.post_text
     or old.platform is distinct from new.platform
     or old.slot_rank is distinct from new.slot_rank
     or old.recommendation_score is distinct from new.recommendation_score
     or old.confidence is distinct from new.confidence
     or old.supporting_sample_size is distinct from new.supporting_sample_size
     or old.metrics_status is distinct from new.metrics_status
  then
    new.sheet_exported_at := null;
  end if;

  return new;
end;
$$;

drop trigger if exists
  reset_schedule_proposal_sheet_export_trigger
on public.schedule_change_proposals;

create trigger reset_schedule_proposal_sheet_export_trigger
before update on public.schedule_change_proposals
for each row
execute function public.reset_schedule_proposal_sheet_export();

create or replace view public.pending_schedule_proposal_exports
with (security_invoker = false)
as
select
  id as proposal_id,
  approval_status,
  platform,
  content_format,
  buffer_post_id,
  post_text,
  external_link,
  current_due_at_utc,
  current_due_at_local,
  proposed_due_at_utc,
  proposed_due_at_local,
  trim(to_char(
    current_due_at_local,
    'FMDay, FMMonth DD at FMHH12:MI AM'
  )) as current_schedule_label,
  trim(to_char(
    proposed_due_at_local,
    'FMDay, FMMonth DD at FMHH12:MI AM'
  )) as proposed_schedule_label,
  slot_rank,
  source_recommendation_rank,
  recommendation_score,
  confidence,
  supporting_sample_size,
  metrics_status,
  timezone_name,
  generated_at,
  sheet_exported_at
from public.schedule_change_proposals
where approval_status = 'Pending'
  and sheet_exported_at is null
order by
  proposed_due_at_utc asc,
  platform asc;

create or replace function public.mark_schedule_proposal_exported(
  p_proposal_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.schedule_change_proposals
  set
    sheet_exported_at = now(),
    updated_at = now()
  where id = p_proposal_id
    and approval_status = 'Pending'
    and sheet_exported_at is null;

  return found;
end;
$$;

revoke all on function public.reset_schedule_proposal_sheet_export()
  from public, anon, authenticated;

revoke all on public.pending_schedule_proposal_exports
  from public, anon, authenticated;

revoke all on function public.mark_schedule_proposal_exported(uuid)
  from public, anon, authenticated;

grant select on public.pending_schedule_proposal_exports
  to creator_dashboard_reader;

grant execute on function public.mark_schedule_proposal_exported(uuid)
  to service_role;

commit;
