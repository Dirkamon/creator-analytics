-- Creator Analytics
-- Regression coverage for migration 037
-- File: Tests/Database/037_add_controlled_web_schedule_decisions_regression.sql
--
-- Run after migrations 001-037 in a fresh PostgreSQL 17-compatible sandbox.
-- Proves that Schedule Approvals decisions are audited, version-checked,
-- preflighted, and mutually exclusive with the existing Google Sheets export
-- path. All fixtures roll back.

begin;

set local timezone = 'UTC';
set local statement_timeout = '90s';
set local lock_timeout = '5s';


-- ---------------------------------------------------------------------------
-- 1. Security and private projection shape
-- ---------------------------------------------------------------------------

do $test$
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_approver'
      and rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
  ) then
    raise exception 'Migration 037 approver role is not fail-closed';
  end if;

  if not pg_catalog.has_function_privilege(
       'creator_analytics_web_approver',
       'public.process_schedule_proposal_decision_for_web(uuid,text,timestamptz,text)',
       'EXECUTE'
     ) then
    raise exception 'Approver cannot execute the exact decision wrapper';
  end if;

  if pg_catalog.has_table_privilege(
       'creator_analytics_web_approver',
       'public.schedule_change_proposals',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'creator_analytics_web_approver',
       'public.web_schedule_decision_events',
       'SELECT,INSERT,UPDATE,DELETE'
     ) then
    raise exception 'Approver has direct table access';
  end if;

  if pg_catalog.has_function_privilege(
       'creator_analytics_web_approver',
       'public.set_schedule_proposal_decision(uuid,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'creator_analytics_web_approver',
       'public.set_exported_schedule_proposal_decision(uuid,text)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'creator_analytics_web_approver',
       'public.claim_pending_schedule_proposal_exports(integer)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'creator_analytics_web_approver',
       'public.mark_schedule_proposal_exported(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'Approver can execute an unrelated scheduling function';
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
    raise exception 'Service role retains the non-atomic export contract';
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
    raise exception 'Service role cannot execute the atomic export contract';
  end if;

  if not pg_catalog.has_table_privilege(
       'creator_analytics_web_reader',
       'creator_app.pending_schedule_proposal_exports',
       'SELECT'
     ) then
    raise exception 'Web reader cannot inspect safe proposal ownership state';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'creator_app'
      and table_name = 'pending_schedule_proposal_exports'
      and column_name like '%token%'
  ) then
    raise exception 'Private proposal projection exposes a claim token';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Transactional fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (buffer_organization_id, name)
values ('MIGRATION_037_ORG', 'Migration 037 fixture');

insert into public.channels (
  buffer_channel_id,
  buffer_organization_id,
  service,
  name,
  timezone
)
values (
  'MIGRATION_037_CHANNEL',
  'MIGRATION_037_ORG',
  'tiktok',
  'migration_037',
  'America/Denver'
);

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  channel_service,
  post_text,
  status,
  due_at,
  last_synced_at,
  schedule_evaluated_at
)
select
  fixture.buffer_post_id,
  'MIGRATION_037_ORG',
  'MIGRATION_037_CHANNEL',
  'tiktok',
  fixture.post_text,
  'scheduled',
  pg_catalog.now() + fixture.current_offset,
  pg_catalog.now(),
  pg_catalog.now()
from (values
  ('MIGRATION_037_CLAIM'::text, 'Make claim fixture'::text, interval '10 days'),
  ('MIGRATION_037_APPROVE'::text, 'Web approval fixture'::text, interval '11 days'),
  ('MIGRATION_037_REJECT'::text, 'Web rejection fixture'::text, interval '12 days'),
  ('MIGRATION_037_STALE'::text, 'Stale page fixture'::text, interval '13 days'),
  ('MIGRATION_037_BLOCKED'::text, 'Failed preflight fixture'::text, interval '14 days')
) fixture(buffer_post_id, post_text, current_offset);

insert into public.schedule_change_proposals (
  id,
  buffer_post_id,
  platform,
  content_format,
  post_text,
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
  fixture.proposal_id,
  fixture.buffer_post_id,
  'tiktok',
  'short_form',
  post_record.post_text,
  post_record.due_at,
  post_record.due_at at time zone 'America/Denver',
  pg_catalog.now() + fixture.proposed_offset,
  (pg_catalog.now() + fixture.proposed_offset)
    at time zone 'America/Denver',
  1,
  1,
  0.9,
  'High',
  20,
  'Fresh',
  'America/Denver',
  'Pending',
  pg_catalog.now(),
  fixture.version_at
from (values
  (
    '03700000-0000-0000-0000-000000000001'::uuid,
    'MIGRATION_037_CLAIM'::text,
    interval '30 days',
    '2037-01-01 00:00:01+00'::timestamptz
  ),
  (
    '03700000-0000-0000-0000-000000000002'::uuid,
    'MIGRATION_037_APPROVE'::text,
    interval '32 days',
    '2037-01-01 00:00:02+00'::timestamptz
  ),
  (
    '03700000-0000-0000-0000-000000000003'::uuid,
    'MIGRATION_037_REJECT'::text,
    interval '34 days',
    '2037-01-01 00:00:03+00'::timestamptz
  ),
  (
    '03700000-0000-0000-0000-000000000004'::uuid,
    'MIGRATION_037_STALE'::text,
    interval '36 days',
    '2037-01-01 00:00:04+00'::timestamptz
  ),
  (
    '03700000-0000-0000-0000-000000000005'::uuid,
    'MIGRATION_037_BLOCKED'::text,
    interval '38 days',
    '2037-01-01 00:00:05+00'::timestamptz
  )
) fixture(proposal_id, buffer_post_id, proposed_offset, version_at)
join public.posts post_record
  on post_record.buffer_post_id = fixture.buffer_post_id;

create temporary table migration_037_claim_result
on commit drop
as
select *
from public.claim_pending_schedule_proposal_exports(1)
with no data;

create temporary table migration_037_finalize_result (
  attempt text primary key,
  changed boolean not null
) on commit drop;

create temporary table migration_037_second_claim
on commit drop
as
select *
from public.claim_pending_schedule_proposal_exports(100)
with no data;

grant select, insert on migration_037_claim_result to service_role;
grant select, insert on migration_037_finalize_result to service_role;
grant select, insert, truncate on migration_037_second_claim to service_role;

grant service_role
to current_user
with set true, inherit false;

grant creator_analytics_web_approver
to current_user
with set true, inherit false;


-- ---------------------------------------------------------------------------
-- 3. Make claims a row exactly once and blocks the app
-- ---------------------------------------------------------------------------

set local role service_role;

insert into pg_temp.migration_037_claim_result
select *
from public.claim_pending_schedule_proposal_exports(1);

reset role;

do $test$
begin
  if (
    select count(*)
    from pg_temp.migration_037_claim_result
  ) <> 1 or not exists (
    select 1
    from pg_temp.migration_037_claim_result
    where proposal_id = '03700000-0000-0000-0000-000000000001'
      and claim_token is not null
  ) then
    raise exception 'Atomic proposal claim returned the wrong row or token';
  end if;

  if not exists (
    select 1
    from creator_app.pending_schedule_proposal_exports
    where proposal_id = '03700000-0000-0000-0000-000000000001'
      and queue_state = 'export_in_progress'
      and claimed_at is not null
  ) then
    raise exception 'Private projection does not show Make ownership';
  end if;
end;
$test$;

set local role creator_analytics_web_approver;

do $test$
begin
  perform *
  from public.process_schedule_proposal_decision_for_web(
    '03700000-0000-0000-0000-000000000001',
    'Approved',
    '2037-01-01 00:00:01+00',
    'operator@example.invalid'
  );
  raise exception 'Expected Make-owned proposal rejection';
exception
  when sqlstate 'P4003' then null;
end;
$test$;

reset role;

do $test$
begin
  if exists (
    select 1
    from public.web_schedule_decision_events
    where proposal_id = '03700000-0000-0000-0000-000000000001'
  ) or not exists (
    select 1
    from public.schedule_change_proposals
    where id = '03700000-0000-0000-0000-000000000001'
      and approval_status = 'Pending'
  ) then
    raise exception 'Rejected Make-owned web decision changed state or audit';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 4. Exact-token finalization and Sheet-owned decisions
-- ---------------------------------------------------------------------------

set local role service_role;

insert into pg_temp.migration_037_finalize_result (attempt, changed)
values (
  'wrong-token',
  public.mark_schedule_proposal_exported(
    '03700000-0000-0000-0000-000000000001',
    '03700000-0000-0000-0000-000000000099'
  )
);

insert into pg_temp.migration_037_finalize_result (attempt, changed)
select
  'correct-token',
  public.mark_schedule_proposal_exported(proposal_id, claim_token)
from pg_temp.migration_037_claim_result;

insert into pg_temp.migration_037_finalize_result (attempt, changed)
select
  'duplicate-finalize',
  public.mark_schedule_proposal_exported(proposal_id, claim_token)
from pg_temp.migration_037_claim_result;

reset role;

do $test$
begin
  if (
    select changed from pg_temp.migration_037_finalize_result
    where attempt = 'wrong-token'
  ) or not (
    select changed from pg_temp.migration_037_finalize_result
    where attempt = 'correct-token'
  ) or (
    select changed from pg_temp.migration_037_finalize_result
    where attempt = 'duplicate-finalize'
  ) then
    raise exception 'Proposal export finalization is not exact and idempotent';
  end if;
end;
$test$;

set local role service_role;

do $test$
begin
  if not public.set_exported_schedule_proposal_decision(
    '03700000-0000-0000-0000-000000000001',
    'Rejected'
  ) then
    raise exception 'Sheet-owned proposal could not record its decision';
  end if;

  if public.set_exported_schedule_proposal_decision(
    '03700000-0000-0000-0000-000000000004',
    'Approved'
  ) then
    raise exception 'Sheet decision changed an unexported app-owned row';
  end if;
end;
$test$;

reset role;


-- ---------------------------------------------------------------------------
-- 5. Web decisions are version-checked, audited, and preflighted
-- ---------------------------------------------------------------------------

set local role creator_analytics_web_approver;

select *
from public.process_schedule_proposal_decision_for_web(
  '03700000-0000-0000-0000-000000000002',
  'Approved',
  '2037-01-01 00:00:02+00',
  'OPERATOR@EXAMPLE.INVALID'
);

select *
from public.process_schedule_proposal_decision_for_web(
  '03700000-0000-0000-0000-000000000003',
  'Rejected',
  '2037-01-01 00:00:03+00',
  'operator@example.invalid'
);

do $test$
begin
  perform *
  from public.process_schedule_proposal_decision_for_web(
    '03700000-0000-0000-0000-000000000002',
    'Approved',
    '2037-01-01 00:00:02+00',
    'operator@example.invalid'
  );
  raise exception 'Expected duplicate-click rejection';
exception
  when sqlstate 'P4001' then null;
end;
$test$;

do $test$
begin
  perform *
  from public.process_schedule_proposal_decision_for_web(
    '03700000-0000-0000-0000-000000000004',
    'Rejected',
    '2037-01-01 00:00:03+00',
    'operator@example.invalid'
  );
  raise exception 'Expected stale-page rejection';
exception
  when sqlstate 'P4005' then null;
end;
$test$;

reset role;

update public.posts
set due_at = due_at + interval '1 hour'
where buffer_post_id = 'MIGRATION_037_BLOCKED';

set local role creator_analytics_web_approver;

do $test$
begin
  perform *
  from public.process_schedule_proposal_decision_for_web(
    '03700000-0000-0000-0000-000000000005',
    'Approved',
    '2037-01-01 00:00:05+00',
    'operator@example.invalid'
  );
  raise exception 'Expected current-preflight rejection';
exception
  when sqlstate 'P4006' then null;
end;
$test$;

reset role;

do $test$
begin
  if not exists (
    select 1
    from public.schedule_change_proposals
    where id = '03700000-0000-0000-0000-000000000002'
      and approval_status = 'Approved'
      and approved_at is not null
  ) or not exists (
    select 1
    from public.schedule_change_proposals
    where id = '03700000-0000-0000-0000-000000000003'
      and approval_status = 'Rejected'
      and rejected_at is not null
  ) then
    raise exception 'Successful web decisions were not recorded correctly';
  end if;

  if (
    select count(*)
    from public.web_schedule_decision_events
    where proposal_id in (
      '03700000-0000-0000-0000-000000000002',
      '03700000-0000-0000-0000-000000000003'
    )
  ) <> 2 or not exists (
    select 1
    from public.web_schedule_decision_events
    where proposal_id = '03700000-0000-0000-0000-000000000002'
      and actor_email = 'operator@example.invalid'
      and decision = 'Approved'
      and previous_status = 'Pending'
  ) then
    raise exception 'Web decision audit details are incorrect';
  end if;

  if exists (
    select 1
    from public.web_schedule_decision_events
    where proposal_id in (
      '03700000-0000-0000-0000-000000000004',
      '03700000-0000-0000-0000-000000000005'
    )
  ) or exists (
    select 1
    from public.schedule_change_proposals
    where id in (
      '03700000-0000-0000-0000-000000000004',
      '03700000-0000-0000-0000-000000000005'
    )
      and approval_status <> 'Pending'
  ) then
    raise exception 'Rejected web decisions changed state or audit';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 6. App-owned rows cannot later be claimed by Make
-- ---------------------------------------------------------------------------

set local role service_role;

insert into pg_temp.migration_037_second_claim
select *
from public.claim_pending_schedule_proposal_exports(100);

reset role;

do $test$
begin
  if exists (
    select 1
    from pg_temp.migration_037_second_claim
    where proposal_id in (
      '03700000-0000-0000-0000-000000000002',
      '03700000-0000-0000-0000-000000000003'
    )
  ) then
    raise exception 'Make claimed a proposal already decided in the app';
  end if;
end;
$test$;

revoke service_role
from current_user
granted by current_user;

revoke creator_analytics_web_approver
from current_user
granted by current_user;

rollback;
