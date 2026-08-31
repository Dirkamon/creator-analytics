-- Creator Analytics
-- Regression coverage for migration 034
-- File: Tests/Database/034_restrict_internal_schedule_generator_execution_regression.sql
--
-- First execute the migration-032 regression unchanged. It proves scheduling
-- output, collision/capacity boundaries, proposal history, the 19-column Make
-- contract, concurrency structure, and transactional fixture cleanup. That
-- included script ends in ROLLBACK. This script then reproduces dirty hosted
-- function ACLs, applies migration 034's exact normalization, proves all other
-- contracts are unchanged, and also ends in ROLLBACK.

\ir 032_optimize_range_aware_schedule_proposal_generation_regression.sql

begin;

set local timezone = 'UTC';
set local statement_timeout = '90s';
set local lock_timeout = '5s';


-- ---------------------------------------------------------------------------
-- 1. Preconditions and immutable-contract snapshots
-- ---------------------------------------------------------------------------

do $test$
declare
  v_missing text;
  v_definition text;
begin
  select string_agg(required.role_name, ', ' order by required.role_name)
  into v_missing
  from (values
    ('anon'::text),
    ('authenticated'::text),
    ('service_role'::text),
    ('creator_dashboard_reader'::text),
    ('creator_analytics_web_reader'::text),
    ('creator_analytics_web_view_owner'::text)
  ) required(role_name)
  where not exists (
    select 1
    from pg_catalog.pg_roles role_record
    where role_record.rolname = required.role_name
  );

  if v_missing is not null then
    raise exception 'Migration 034 required roles are missing: %', v_missing;
  end if;

  if to_regprocedure(
       'public.create_collision_safe_schedule_proposals(integer,date,date)'
     ) is null
     or to_regprocedure(
       'public.create_content_aware_schedule_proposals(integer)'
     ) is null
     or to_regprocedure(
       'public.refresh_schedule_proposals(date,integer)'
     ) is null then
    raise exception 'Migration 034 required functions are missing';
  end if;

  select lower(pg_catalog.pg_get_functiondef(
    'public.refresh_schedule_proposals(date,integer)'::regprocedure
  ))
  into v_definition;

  if position(
       'public.create_collision_safe_schedule_proposals'
       in v_definition
     ) = 0 then
    raise exception
      'Make-facing refresh wrapper no longer delegates to the internal generator';
  end if;
end;
$test$;

create temporary table migration_034_function_snapshot
on commit drop
as
select
  function_record.oid,
  function_record.oid::regprocedure::text as function_identity,
  function_record.proowner,
  function_record.proacl,
  function_record.prosecdef,
  function_record.proconfig,
  function_record.provolatile,
  function_record.prorettype,
  function_record.proargtypes,
  pg_catalog.pg_get_functiondef(function_record.oid) as function_definition,
  pg_catalog.obj_description(function_record.oid, 'pg_proc') as description
from pg_catalog.pg_proc function_record
where function_record.oid in (
  'public.create_collision_safe_schedule_proposals(integer,date,date)'
    ::regprocedure,
  'public.create_content_aware_schedule_proposals(integer)'
    ::regprocedure,
  'public.refresh_schedule_proposals(date,integer)'
    ::regprocedure
);

create temporary table migration_034_relation_counts
on commit drop
as
select 'posts'::text as relation_name, count(*)::bigint as row_count
from public.posts
union all
select 'schedule_change_proposals', count(*)::bigint
from public.schedule_change_proposals;

do $test$
declare
  v_make_contract text[];
begin
  if (select count(*) from migration_034_function_snapshot) <> 3 then
    raise exception 'Migration 034 function snapshot is incomplete';
  end if;

  select array_agg(
    format('%s:%s:%s', column_name, data_type, udt_name)
    order by ordinal_position
  )
  into v_make_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if v_make_contract is distinct from array[
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
    raise exception 'Migration 034 initial Make contract changed: %',
      v_make_contract;
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Reproduce dirty hosted default-privilege ACLs
-- ---------------------------------------------------------------------------

create role migration_034_unexpected_executor
  nologin
  nosuperuser
  nocreatedb
  nocreaterole
  noinherit
  noreplication
  nobypassrls;

grant execute on function
  public.create_collision_safe_schedule_proposals(integer,date,date)
to
  public,
  anon,
  authenticated,
  service_role,
  creator_dashboard_reader,
  creator_analytics_web_reader,
  creator_analytics_web_view_owner,
  migration_034_unexpected_executor;

do $test$
declare
  v_dirty_grantees text[];
begin
  select array_agg(
    case
      when acl.grantee = 0::oid then 'PUBLIC'
      else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
    end
    order by
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end
  )
  into v_dirty_grantees
  from pg_catalog.pg_proc function_record
  cross join lateral pg_catalog.aclexplode(
    coalesce(
      function_record.proacl,
      pg_catalog.acldefault('f', function_record.proowner)
    )
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where function_record.oid =
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure
    and acl.grantee <> function_record.proowner
    and acl.privilege_type = 'EXECUTE';

  if v_dirty_grantees is distinct from array[
    'PUBLIC',
    'anon',
    'authenticated',
    'creator_analytics_web_reader',
    'creator_analytics_web_view_owner',
    'creator_dashboard_reader',
    'migration_034_unexpected_executor',
    'service_role'
  ]::text[] then
    raise exception
      'Migration 034 dirty ACL fixture is incomplete: %',
      v_dirty_grantees;
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 3. Apply migration 034's exact ACL normalization
-- ---------------------------------------------------------------------------

do $migration_034_revoke$
declare
  v_grantee record;
begin
  for v_grantee in
    select distinct
      acl.grantee as grantee_oid,
      role_record.rolname as grantee_name
    from pg_catalog.pg_proc function_record
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        function_record.proacl,
        pg_catalog.acldefault('f', function_record.proowner)
      )
    ) acl
    left join pg_catalog.pg_roles role_record
      on role_record.oid = acl.grantee
    where function_record.oid =
      'public.create_collision_safe_schedule_proposals(integer,date,date)'
        ::regprocedure
      and acl.grantee <> function_record.proowner
  loop
    if v_grantee.grantee_oid = 0::oid then
      execute
        'revoke all privileges on function public.create_collision_safe_schedule_proposals(integer,date,date) from public';
    elsif v_grantee.grantee_name is null then
      raise exception 'Cannot resolve dirty ACL grantee OID %',
        v_grantee.grantee_oid;
    else
      execute format(
        'revoke all privileges on function public.create_collision_safe_schedule_proposals(integer,date,date) from %I',
        v_grantee.grantee_name
      );
    end if;
  end loop;
end;
$migration_034_revoke$;


-- ---------------------------------------------------------------------------
-- 4. ACL, wrapper, security, data, and contract assertions
-- ---------------------------------------------------------------------------

do $test$
declare
  v_acl text[];
  v_contract_mismatch text;
  v_make_contract text[];
  v_wrapper_acl text[];
  v_role_name text;
begin
  select array_agg(
    format(
      '%s:%s:%s',
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    )
    order by
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      acl.is_grantable
  )
  into v_acl
  from pg_catalog.pg_proc function_record
  cross join lateral pg_catalog.aclexplode(
    coalesce(
      function_record.proacl,
      pg_catalog.acldefault('f', function_record.proowner)
    )
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where function_record.oid =
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure
    and acl.grantee <> function_record.proowner;

  if v_acl is not null then
    raise exception
      'Internal generator retained direct non-owner privileges: %', v_acl;
  end if;

  foreach v_role_name in array array[
    'anon',
    'authenticated',
    'service_role',
    'creator_dashboard_reader',
    'creator_analytics_web_reader',
    'creator_analytics_web_view_owner',
    'migration_034_unexpected_executor'
  ]::text[] loop
    if pg_catalog.has_function_privilege(
         v_role_name,
         'public.create_collision_safe_schedule_proposals(integer,date,date)',
         'EXECUTE'
       ) then
      raise exception
        'Role % can still execute the internal generator', v_role_name;
    end if;
  end loop;

  with current_contract as (
    select
      function_record.oid,
      function_record.oid::regprocedure::text as function_identity,
      function_record.proowner,
      function_record.proacl,
      function_record.prosecdef,
      function_record.proconfig,
      function_record.provolatile,
      function_record.prorettype,
      function_record.proargtypes,
      pg_catalog.pg_get_functiondef(function_record.oid)
        as function_definition,
      pg_catalog.obj_description(function_record.oid, 'pg_proc')
        as description
    from pg_catalog.pg_proc function_record
    where function_record.oid in (
      'public.create_collision_safe_schedule_proposals(integer,date,date)'
        ::regprocedure,
      'public.create_content_aware_schedule_proposals(integer)'
        ::regprocedure,
      'public.refresh_schedule_proposals(date,integer)'
        ::regprocedure
    )
  )
  select string_agg(
    coalesce(before.function_identity, after.function_identity),
    ', '
    order by coalesce(before.function_identity, after.function_identity)
  )
  into v_contract_mismatch
  from migration_034_function_snapshot before
  full join current_contract after
    on after.oid = before.oid
  where before.function_identity is distinct from after.function_identity
     or before.proowner is distinct from after.proowner
     or before.prosecdef is distinct from after.prosecdef
     or before.proconfig is distinct from after.proconfig
     or before.provolatile is distinct from after.provolatile
     or before.prorettype is distinct from after.prorettype
     or before.proargtypes is distinct from after.proargtypes
     or before.function_definition is distinct from after.function_definition
     or before.description is distinct from after.description
     or (
       before.function_identity <>
         'create_collision_safe_schedule_proposals(integer,date,date)'
       and before.proacl is distinct from after.proacl
     );

  if v_contract_mismatch is not null then
    raise exception
      'Migration 034 changed a non-ACL function contract: %',
      v_contract_mismatch;
  end if;

  select array_agg(
    format(
      '%s:%s:%s:%s',
      function_record.oid::regprocedure::text,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    )
    order by
      function_record.oid::regprocedure::text,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      acl.is_grantable
  )
  into v_wrapper_acl
  from pg_catalog.pg_proc function_record
  cross join lateral pg_catalog.aclexplode(
    coalesce(
      function_record.proacl,
      pg_catalog.acldefault('f', function_record.proowner)
    )
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where function_record.oid in (
    'public.create_content_aware_schedule_proposals(integer)'
      ::regprocedure,
    'public.refresh_schedule_proposals(date,integer)'
      ::regprocedure
  )
    and acl.grantee <> function_record.proowner;

  if v_wrapper_acl is distinct from array[
    'create_content_aware_schedule_proposals(integer):service_role:EXECUTE:NO',
    'refresh_schedule_proposals(date,integer):service_role:EXECUTE:NO'
  ]::text[] then
    raise exception 'Public-wrapper ACL changed: %', v_wrapper_acl;
  end if;

  select array_agg(
    format('%s:%s:%s', column_name, data_type, udt_name)
    order by ordinal_position
  )
  into v_make_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if v_make_contract is distinct from array[
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
    raise exception 'Migration 034 changed the Make contract: %',
      v_make_contract;
  end if;

  if exists (
    select 1
    from migration_034_relation_counts before
    full join (
      select 'posts'::text as relation_name, count(*)::bigint as row_count
      from public.posts
      union all
      select 'schedule_change_proposals', count(*)::bigint
      from public.schedule_change_proposals
    ) after
      using (relation_name)
    where before.row_count is distinct from after.row_count
  ) then
    raise exception
      'Migration 034 ACL normalization changed posts or proposal history';
  end if;
end;
$test$;

-- A rolled-back behavioral suite and this transaction must leave no fixtures.
rollback;
