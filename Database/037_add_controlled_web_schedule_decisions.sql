-- Creator Analytics
-- Controlled web schedule decisions with atomic Sheet export ownership
-- File: Database/037_add_controlled_web_schedule_decisions.sql
--
-- Adds a dedicated, passwordless-by-default web approver role, one audited
-- decision wrapper, and an atomic claim/finalize protocol for Make. Pending
-- proposals are owned by exactly one path: the web app before claim, or the
-- existing Google Sheets workflow after Make claims the row.

begin;


-- ---------------------------------------------------------------------------
-- 1. Dedicated server-only approver role
-- ---------------------------------------------------------------------------

do $migration_037_role$
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_approver'
  ) then
    create role creator_analytics_web_approver
      login
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls;
  end if;
end;
$migration_037_role$;

do $migration_037_role_safety$
declare
  v_unsafe text;
begin
  select role_record.rolname
  into v_unsafe
  from pg_catalog.pg_roles role_record
  where role_record.rolname = 'creator_analytics_web_approver'
    and (
      role_record.rolsuper
      or role_record.rolcreatedb
      or role_record.rolcreaterole
      or role_record.rolreplication
      or role_record.rolbypassrls
    );

  if v_unsafe is not null then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 refuses unsafe approver role attributes';
  end if;

  select pg_catalog.string_agg(
    pg_catalog.format(
      '%s->%s (admin=%s, inherit=%s, set=%s)',
      member_role.rolname,
      granted_role.rolname,
      membership.admin_option,
      membership.inherit_option,
      membership.set_option
    ),
    ', ' order by granted_role.rolname, member_role.rolname
  )
  into v_unsafe
  from pg_catalog.pg_auth_members membership
  join pg_catalog.pg_roles granted_role
    on granted_role.oid = membership.roleid
  join pg_catalog.pg_roles member_role
    on member_role.oid = membership.member
  where member_role.rolname = 'creator_analytics_web_approver'
     or granted_role.rolname = 'creator_analytics_web_approver';

  if v_unsafe is not null then
    raise exception using
      errcode = '42501',
      message = pg_catalog.format(
        'Migration 037 refuses unsafe approver role memberships: %s',
        v_unsafe
      );
  end if;
end;
$migration_037_role_safety$;

alter role creator_analytics_web_approver
  login
  noinherit;

alter role creator_analytics_web_approver
  set statement_timeout = '15s';

alter role creator_analytics_web_approver
  set idle_in_transaction_session_timeout = '15s';

alter role creator_analytics_web_approver
  set search_path = pg_catalog;

grant connect on database postgres
to creator_analytics_web_approver;

grant usage on schema public
to creator_analytics_web_approver;


-- ---------------------------------------------------------------------------
-- 2. Durable ownership and audit state
-- ---------------------------------------------------------------------------

alter table public.schedule_change_proposals
  add column if not exists sheet_export_claim_token uuid,
  add column if not exists sheet_export_claimed_at timestamptz;

do $migration_037_claim_pair_constraint$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conrelid =
          'public.schedule_change_proposals'::regclass
      and constraint_record.conname =
          'schedule_proposals_sheet_claim_pair_check'
  ) then
    alter table public.schedule_change_proposals
      add constraint schedule_proposals_sheet_claim_pair_check
      check (
        (sheet_export_claim_token is null) =
        (sheet_export_claimed_at is null)
      );
  end if;
end;
$migration_037_claim_pair_constraint$;

create unique index if not exists
  schedule_proposals_sheet_claim_token_unique_idx
on public.schedule_change_proposals (sheet_export_claim_token)
where sheet_export_claim_token is not null;

create index if not exists
  schedule_proposals_pending_sheet_claim_idx
on public.schedule_change_proposals (
  proposed_due_at_utc,
  platform,
  id
)
where approval_status = 'Pending'
  and sheet_exported_at is null
  and sheet_export_claim_token is null;

create table if not exists public.web_schedule_decision_events (
  id bigint generated always as identity primary key,
  proposal_id uuid not null,
  buffer_post_id text not null,
  actor_email text not null,
  decision text not null
    check (decision in ('Approved', 'Rejected')),
  expected_updated_at timestamptz not null,
  previous_status text not null,
  created_at timestamptz not null default now()
);

alter table public.web_schedule_decision_events enable row level security;

create index if not exists web_schedule_decision_events_proposal_created_idx
  on public.web_schedule_decision_events (proposal_id, created_at desc);

revoke all on table public.web_schedule_decision_events
from
  public,
  anon,
  authenticated,
  service_role,
  creator_dashboard_reader,
  creator_analytics_web_reader,
  creator_analytics_web_view_owner,
  creator_analytics_web_labeler,
  creator_analytics_web_approver;


-- Material proposal changes invalidate any incomplete external claim. If Make
-- already wrote the stale Sheet row, its finalization will fail and require
-- manual review instead of recording a misleading successful export.
create or replace function public.reset_schedule_proposal_sheet_export()
returns trigger
language plpgsql
set search_path = ''
as $function$
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
    new.sheet_export_claim_token := null;
    new.sheet_export_claimed_at := null;
  elsif new.sheet_exported_at is not null then
    new.sheet_export_claim_token := null;
    new.sheet_export_claimed_at := null;
  end if;

  return new;
end;
$function$;


-- ---------------------------------------------------------------------------
-- 3. Atomic Make claim/finalize contract
-- ---------------------------------------------------------------------------

create or replace function public.claim_pending_schedule_proposal_exports(
  p_limit integer default 100
)
returns table (
  claim_token uuid,
  proposal_id uuid,
  approval_status text,
  platform text,
  content_format text,
  buffer_post_id text,
  post_text text,
  external_link text,
  current_due_at_utc timestamptz,
  current_due_at_local timestamp without time zone,
  proposed_due_at_utc timestamptz,
  proposed_due_at_local timestamp without time zone,
  current_schedule_label text,
  proposed_schedule_label text,
  slot_rank integer,
  source_recommendation_rank integer,
  recommendation_score numeric,
  confidence text,
  supporting_sample_size integer,
  metrics_status text,
  timezone_name text,
  generated_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 200 then
    raise exception using
      errcode = '22023',
      message = 'p_limit must be between 1 and 200';
  end if;

  return query
  with candidates as (
    select proposal.id
    from public.schedule_change_proposals proposal
    where proposal.approval_status = 'Pending'
      and proposal.sheet_exported_at is null
      and proposal.sheet_export_claim_token is null
    order by
      proposal.proposed_due_at_utc asc,
      proposal.platform asc,
      proposal.id asc
    for update skip locked
    limit p_limit
  ),
  claimed as (
    update public.schedule_change_proposals proposal
    set
      sheet_export_claim_token = pg_catalog.gen_random_uuid(),
      sheet_export_claimed_at = pg_catalog.clock_timestamp(),
      updated_at = pg_catalog.now()
    from candidates
    where proposal.id = candidates.id
    returning proposal.*
  )
  select
    claimed.sheet_export_claim_token,
    claimed.id,
    claimed.approval_status,
    claimed.platform,
    claimed.content_format,
    claimed.buffer_post_id,
    claimed.post_text,
    claimed.external_link,
    claimed.current_due_at_utc,
    claimed.current_due_at_local,
    claimed.proposed_due_at_utc,
    claimed.proposed_due_at_local,
    pg_catalog.btrim(pg_catalog.to_char(
      claimed.current_due_at_local,
      'FMDay, FMMonth DD at FMHH12:MI AM'
    )),
    pg_catalog.btrim(pg_catalog.to_char(
      claimed.proposed_due_at_local,
      'FMDay, FMMonth DD at FMHH12:MI AM'
    )),
    claimed.slot_rank,
    claimed.source_recommendation_rank,
    claimed.recommendation_score,
    claimed.confidence,
    claimed.supporting_sample_size,
    claimed.metrics_status,
    claimed.timezone_name,
    claimed.generated_at
  from claimed
  order by
    claimed.proposed_due_at_utc asc,
    claimed.platform asc,
    claimed.id asc;
end;
$function$;

create or replace function public.mark_schedule_proposal_exported(
  p_proposal_id uuid,
  p_claim_token uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_updated integer;
begin
  update public.schedule_change_proposals
  set
    sheet_exported_at = pg_catalog.now(),
    sheet_export_claim_token = null,
    sheet_export_claimed_at = null,
    updated_at = pg_catalog.now()
  where id = p_proposal_id
    and approval_status = 'Pending'
    and sheet_exported_at is null
    and sheet_export_claim_token = p_claim_token;

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$function$;

-- The Sheets-to-Supabase decision path gets a new, narrower function. The
-- original internal helper remains available to its owner for historical
-- migrations and regression workflows, but service_role loses EXECUTE on it.
-- This keeps a stale Sheet row from overwriting a proposal decided in the app.
create or replace function public.set_exported_schedule_proposal_decision(
  p_proposal_id uuid,
  p_decision text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_normalized_decision text;
  v_updated integer;
begin
  v_normalized_decision := pg_catalog.initcap(
    pg_catalog.lower(pg_catalog.btrim(p_decision))
  );

  if v_normalized_decision not in ('Pending', 'Approved', 'Rejected') then
    raise exception using
      errcode = '22023',
      message = 'Decision must be Pending, Approved, or Rejected';
  end if;

  update public.schedule_change_proposals
  set
    approval_status = v_normalized_decision,
    approved_at = case
      when v_normalized_decision = 'Approved' then pg_catalog.now()
      else null
    end,
    rejected_at = case
      when v_normalized_decision = 'Rejected' then pg_catalog.now()
      else null
    end,
    error_message = null,
    updated_at = pg_catalog.now()
  where id = p_proposal_id
    and approval_status <> 'Applied'
    and sheet_exported_at is not null
    and sheet_export_claim_token is null;

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$function$;

revoke select on public.pending_schedule_proposal_exports
from service_role;

revoke execute on function public.mark_schedule_proposal_exported(uuid)
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler,
  creator_analytics_web_approver;

revoke all on function public.claim_pending_schedule_proposal_exports(integer)
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler,
  creator_analytics_web_approver;

revoke all on function public.mark_schedule_proposal_exported(uuid, uuid)
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler,
  creator_analytics_web_approver;

revoke all on function public.set_schedule_proposal_decision(uuid, text)
from public, anon, authenticated, service_role, creator_dashboard_reader,
  creator_analytics_web_reader, creator_analytics_web_view_owner,
  creator_analytics_web_labeler, creator_analytics_web_approver;

revoke all on function public.set_exported_schedule_proposal_decision(uuid, text)
from public, anon, authenticated, service_role, creator_dashboard_reader,
  creator_analytics_web_reader, creator_analytics_web_view_owner,
  creator_analytics_web_labeler, creator_analytics_web_approver;

grant execute on function public.claim_pending_schedule_proposal_exports(integer)
to service_role;

grant execute on function public.mark_schedule_proposal_exported(uuid, uuid)
to service_role;

grant execute on function public.set_exported_schedule_proposal_decision(uuid, text)
to service_role;


-- ---------------------------------------------------------------------------
-- 4. Audited web decision wrapper
-- ---------------------------------------------------------------------------

create or replace function public.process_schedule_proposal_decision_for_web(
  p_proposal_id uuid,
  p_decision text,
  p_expected_updated_at timestamptz,
  p_actor_email text
)
returns table (
  result_status text,
  result_approved_at timestamptz,
  result_rejected_at timestamptz
)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_actor_email text;
  v_decision text;
  v_proposal public.schedule_change_proposals%rowtype;
  v_preflight_ready boolean;
begin
  v_actor_email := pg_catalog.lower(pg_catalog.btrim(p_actor_email));
  v_decision := pg_catalog.initcap(
    pg_catalog.lower(pg_catalog.btrim(p_decision))
  );

  if p_proposal_id is null or p_expected_updated_at is null then
    raise exception using
      errcode = '22023',
      message = 'Proposal identity and expected version are required';
  end if;

  if v_decision not in ('Approved', 'Rejected') then
    raise exception using
      errcode = '22023',
      message = 'Web decision must be Approved or Rejected';
  end if;

  if v_actor_email = ''
     or pg_catalog.length(v_actor_email) > 320
     or v_actor_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception using
      errcode = '22023',
      message = 'Authorized operator email is invalid';
  end if;

  select proposal.*
  into v_proposal
  from public.schedule_change_proposals proposal
  where proposal.id = p_proposal_id
  for update;

  if not found then
    raise exception using
      errcode = 'P4004',
      message = 'Schedule proposal is unavailable';
  end if;

  if v_proposal.approval_status <> 'Pending' then
    raise exception using
      errcode = 'P4001',
      message = 'Schedule proposal already has a decision';
  end if;

  if v_proposal.sheet_exported_at is not null then
    raise exception using
      errcode = 'P4002',
      message = 'Schedule proposal is owned by Google Sheets';
  end if;

  if v_proposal.sheet_export_claim_token is not null then
    raise exception using
      errcode = 'P4003',
      message = 'Schedule proposal is being exported to Google Sheets';
  end if;

  if v_proposal.updated_at <> p_expected_updated_at then
    raise exception using
      errcode = 'P4005',
      message = 'Schedule proposal changed after the page loaded';
  end if;

  update public.schedule_change_proposals
  set
    approval_status = v_decision,
    approved_at = case
      when v_decision = 'Approved' then pg_catalog.now()
      else null
    end,
    rejected_at = case
      when v_decision = 'Rejected' then pg_catalog.now()
      else null
    end,
    error_message = null,
    updated_at = pg_catalog.now()
  where id = p_proposal_id;

  if v_decision = 'Approved' then
    select preflight.is_ready
    into v_preflight_ready
    from public.schedule_change_application_preflight preflight
    where preflight.proposal_id = p_proposal_id;

    if v_preflight_ready is distinct from true then
      raise exception using
        errcode = 'P4006',
        message = 'Schedule proposal failed current application preflight';
    end if;
  end if;

  insert into public.web_schedule_decision_events (
    proposal_id,
    buffer_post_id,
    actor_email,
    decision,
    expected_updated_at,
    previous_status
  )
  values (
    p_proposal_id,
    v_proposal.buffer_post_id,
    v_actor_email,
    v_decision,
    p_expected_updated_at,
    v_proposal.approval_status
  );

  return query
  select
    proposal.approval_status,
    proposal.approved_at,
    proposal.rejected_at
  from public.schedule_change_proposals proposal
  where proposal.id = p_proposal_id;
end;
$function$;

revoke all on function public.process_schedule_proposal_decision_for_web(
  uuid, text, timestamptz, text
)
from
  public,
  anon,
  authenticated,
  service_role,
  creator_dashboard_reader,
  creator_analytics_web_reader,
  creator_analytics_web_view_owner,
  creator_analytics_web_labeler;

grant execute on function public.process_schedule_proposal_decision_for_web(
  uuid, text, timestamptz, text
)
to creator_analytics_web_approver;


-- ---------------------------------------------------------------------------
-- 5. Private export ownership projection (never exposes claim tokens)
-- ---------------------------------------------------------------------------

grant creator_analytics_web_view_owner
to current_user
with set true, inherit false;

set local role creator_analytics_web_view_owner;

grant usage, create on schema creator_app
to creator_analytics_web_view_owner;

grant usage, create on schema creator_app
to session_user;

drop view creator_app.pending_schedule_proposal_exports;

reset role;

create or replace function creator_app.read_schedule_proposal_export_states()
returns table (
  proposal_id uuid,
  queue_state text,
  claimed_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    proposal.id,
    case
      when proposal.sheet_exported_at is not null then 'exported'
      when proposal.sheet_export_claim_token is not null
        then 'export_in_progress'
      else 'pending_export'
    end,
    proposal.sheet_export_claimed_at
  from public.schedule_change_proposals proposal;
$function$;

revoke all on function creator_app.read_schedule_proposal_export_states()
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler,
  creator_analytics_web_approver;

grant execute on function creator_app.read_schedule_proposal_export_states()
to creator_analytics_web_view_owner, creator_analytics_web_reader;

set local role creator_analytics_web_view_owner;

create view creator_app.pending_schedule_proposal_exports
with (security_invoker = false, security_barrier = true)
as
select proposal_id, queue_state, claimed_at
from creator_app.read_schedule_proposal_export_states();

revoke all on creator_app.pending_schedule_proposal_exports
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_labeler,
  creator_analytics_web_approver;

grant select on creator_app.pending_schedule_proposal_exports
to creator_analytics_web_reader;

comment on view creator_app.pending_schedule_proposal_exports is
'Server-only schedule proposal export ownership state. Claim tokens are deliberately omitted.';

revoke usage, create on schema creator_app
from session_user;

reset role;

revoke creator_analytics_web_view_owner
from current_user
granted by current_user;


-- ---------------------------------------------------------------------------
-- 6. Fail-closed postconditions
-- ---------------------------------------------------------------------------

do $migration_037_postconditions$
declare
  v_unexpected text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles role_record
    where role_record.rolname = 'creator_analytics_web_approver'
      and role_record.rolcanlogin
      and not role_record.rolsuper
      and not role_record.rolcreatedb
      and not role_record.rolcreaterole
      and not role_record.rolinherit
      and not role_record.rolreplication
      and not role_record.rolbypassrls
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 approver attributes are not fail-closed';
  end if;

  if not pg_catalog.has_function_privilege(
       'creator_analytics_web_approver',
       'public.process_schedule_proposal_decision_for_web(uuid,text,timestamptz,text)',
       'EXECUTE'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 approver cannot execute its exact wrapper';
  end if;

  if pg_catalog.has_table_privilege(
       'creator_analytics_web_approver',
       'public.schedule_change_proposals',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     )
     or pg_catalog.has_table_privilege(
       'creator_analytics_web_approver',
       'public.web_schedule_decision_events',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 approver received direct table access';
  end if;

  if pg_catalog.has_table_privilege(
       'service_role',
       'public.pending_schedule_proposal_exports',
       'SELECT'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.mark_schedule_proposal_exported(uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.set_schedule_proposal_decision(uuid,text)',
       'EXECUTE'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 left the non-atomic Make export contract available';
  end if;

  if not pg_catalog.has_function_privilege(
       'service_role',
       'public.claim_pending_schedule_proposal_exports(integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.mark_schedule_proposal_exported(uuid,uuid)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.set_exported_schedule_proposal_decision(uuid,text)',
       'EXECUTE'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 service role cannot execute the claim protocol';
  end if;

  select pg_catalog.string_agg(
    function_record.oid::regprocedure::text,
    ', ' order by function_record.oid::regprocedure::text
  )
  into v_unexpected
  from pg_catalog.pg_proc function_record
  join pg_catalog.pg_namespace namespace
    on namespace.oid = function_record.pronamespace
  where namespace.nspname = 'public'
    and function_record.proname in (
      'sync_buffer_posts',
      'sync_buffer_metrics',
      'create_content_item_and_link_posts',
      'process_content_label_payload',
      'process_content_label_row',
      'process_content_label_payload_for_web',
      'claim_pending_label_queue_exports',
      'mark_label_queue_exported',
      'refresh_schedule_proposals',
      'create_content_aware_schedule_proposals',
      'set_schedule_proposal_decision',
      'set_exported_schedule_proposal_decision',
      'claim_pending_schedule_proposal_exports',
      'mark_schedule_proposal_exported',
      'mark_schedule_proposal_applied',
      'mark_schedule_proposal_error'
    )
    and pg_catalog.has_function_privilege(
      'creator_analytics_web_approver',
      function_record.oid,
      'EXECUTE'
    );

  if v_unexpected is not null then
    raise exception using
      errcode = '42501',
      message = pg_catalog.format(
        'Migration 037 approver can execute unrelated public functions: %s',
        v_unexpected
      );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'creator_app'
      and relation.relname = 'pending_schedule_proposal_exports'
      and relation.relkind = 'v'
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'creator_analytics_web_view_owner'
      and relation.reloptions @> array[
        'security_barrier=true',
        'security_invoker=false'
      ]::text[]
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 037 private export-state projection is not fail-closed';
  end if;
end;
$migration_037_postconditions$;

comment on role creator_analytics_web_approver is
'Restricted server-only login for the single audited Phase 4 schedule decision wrapper. Passwords are provisioned outside migrations.';

comment on table public.web_schedule_decision_events is
'Audit trail for server-mediated schedule decisions; never exposed to browser roles.';

comment on function public.claim_pending_schedule_proposal_exports(integer) is
'Atomically claims pending, unexported schedule proposals for Make and returns their Sheet payload plus an opaque finalize token.';

comment on function public.mark_schedule_proposal_exported(uuid, uuid) is
'Finalizes only the exact schedule proposal/token pair previously claimed by Make.';

comment on function public.set_exported_schedule_proposal_decision(uuid, text) is
'Records a Google Sheets decision only after the exact proposal export was finalized.';

comment on function public.process_schedule_proposal_decision_for_web(
  uuid, text, timestamptz, text
) is
'Records an audited Approved or Rejected decision only for an unchanged, unclaimed, unexported Pending proposal; approvals must pass current database preflight.';

commit;
