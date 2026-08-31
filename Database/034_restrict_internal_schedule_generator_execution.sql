-- Creator Analytics
-- Restrict direct execution of the internal schedule generator
-- File: Database/034_restrict_internal_schedule_generator_execution.sql
--
-- Hosted Supabase function default privileges can add service_role EXECUTE to
-- newly created functions. The three-argument collision-safe generator is an
-- internal SECURITY DEFINER implementation detail: callers must use one of its
-- guarded public wrappers. Normalize only this exact function's ACL, and fail
-- closed unless every direct non-owner privilege has been removed.

begin;

create temporary table migration_034_function_contract
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

do $migration_034_preflight$
declare
  v_internal pg_catalog.pg_proc%rowtype;
  v_manual_definition text;
  v_refresh_definition text;
begin
  if (select count(*) from migration_034_function_contract) <> 3 then
    raise exception using
      errcode = '42883',
      message =
        'Migration 034 requires the internal generator and both public wrappers';
  end if;

  select *
  into strict v_internal
  from pg_catalog.pg_proc
  where oid =
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure;

  if not v_internal.prosecdef
     or not (
       v_internal.proconfig @> array['search_path=""']::text[]
     ) then
    raise exception using
      errcode = '42501',
      message =
        'Migration 034 requires the internal generator to remain SECURITY DEFINER with a fixed empty search_path';
  end if;

  select lower(pg_catalog.pg_get_functiondef(
    'public.create_content_aware_schedule_proposals(integer)'::regprocedure
  ))
  into strict v_manual_definition;

  select lower(pg_catalog.pg_get_functiondef(
    'public.refresh_schedule_proposals(date,integer)'::regprocedure
  ))
  into strict v_refresh_definition;

  if position(
       'public.create_collision_safe_schedule_proposals'
       in v_manual_definition
     ) = 0
     or position(
       'public.create_collision_safe_schedule_proposals'
       in v_refresh_definition
     ) = 0 then
    raise exception using
      errcode = '42P13',
      message =
        'Migration 034 requires both public wrappers to delegate to the internal generator';
  end if;
end;
$migration_034_preflight$;

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
      raise exception using
        errcode = '42704',
        message = format(
          'Migration 034 cannot resolve function grantee OID %s',
          v_grantee.grantee_oid
        );
    else
      execute format(
        'revoke all privileges on function public.create_collision_safe_schedule_proposals(integer,date,date) from %I',
        v_grantee.grantee_name
      );
    end if;
  end loop;
end;
$migration_034_revoke$;

do $migration_034_postconditions$
declare
  v_acl text[];
  v_contract_mismatch text;
  v_wrapper_acl text[];
begin
  select array_agg(
    format(
      '%s:%s:%s',
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(
          grantee.rolname,
          'OID ' || acl.grantee::text
        )
      end,
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    )
    order by
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(
          grantee.rolname,
          'OID ' || acl.grantee::text
        )
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
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 034 internal generator still has direct non-owner privileges: %s',
        v_acl::text
      );
  end if;

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
  from migration_034_function_contract before
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
    raise exception using
      errcode = '42P13',
      message = format(
        'Migration 034 changed a function contract other than the internal ACL: %s',
        v_contract_mismatch
      );
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
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 034 public-wrapper ACL mismatch: %s',
        coalesce(v_wrapper_acl::text, 'NULL')
      );
  end if;
end;
$migration_034_postconditions$;

commit;
