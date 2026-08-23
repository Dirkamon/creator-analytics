-- Creator Analytics
-- Regression coverage for migration 030
-- File: Tests/Database/030_normalize_proposal_preview_service_role_permissions_regression.sql
--
-- Run against an isolated PostgreSQL/Supabase-compatible database after
-- migrations 001-030. This transaction deliberately grants service_role every
-- available relation privilege on the two proposal-preview views, reapplies
-- migration 030's correction, proves the exact ACL and unchanged object
-- contracts, and ends in ROLLBACK.

begin;

set local timezone = 'UTC';
set local statement_timeout = '60s';
set local lock_timeout = '5s';


-- ---------------------------------------------------------------------------
-- 1. Preconditions and immutable-object snapshots
-- ---------------------------------------------------------------------------

do $test$
declare
  v_missing text;
begin
  select string_agg(required.role_name, ', ' order by required.role_name)
  into v_missing
  from (values
    ('anon'::text),
    ('authenticated'::text),
    ('service_role'::text),
    ('creator_dashboard_reader'::text)
  ) required(role_name)
  where not exists (
    select 1
    from pg_roles role_record
    where role_record.rolname = required.role_name
  );

  if v_missing is not null then
    raise exception 'Migration 030 required roles are missing: %', v_missing;
  end if;

  select string_agg(expected.view_name, ', ' order by expected.view_name)
  into v_missing
  from (values
    ('looker_content_aware_proposal_preview'::text),
    ('looker_content_aware_proposal_preview_summary'::text)
  ) expected(view_name)
  where not exists (
    select 1
    from pg_class relation
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = expected.view_name
      and relation.relkind = 'v'
  );

  if v_missing is not null then
    raise exception 'Migration 030 target views are missing: %', v_missing;
  end if;

  if to_regclass('public.schedule_slot_reservations') is null
     or to_regclass(
       'public.schedule_change_application_preflight'
     ) is null
     or to_regprocedure(
       'public.find_schedule_slot_conflicts(text,text,timestamptz,integer,uuid)'
     ) is null
     or to_regprocedure(
       'public.get_schedule_reservation_capacity(text,text,timestamptz,text,uuid)'
     ) is null
     or to_regprocedure(
       'public.create_collision_safe_schedule_proposals(integer,date,date)'
     ) is null then
    raise exception 'Migration 029 prerequisite objects are missing';
  end if;
end;
$test$;

create temporary table migration_030_relation_snapshot
on commit drop
as
select
  relation.oid,
  relation.relname,
  relation.relkind,
  relation.relowner,
  relation.reloptions,
  pg_get_viewdef(relation.oid, true) as view_definition
from pg_class relation
join pg_namespace namespace
  on namespace.oid = relation.relnamespace
where namespace.nspname = 'public'
  and relation.relname in (
    'schedule_slot_reservations',
    'looker_content_aware_hybrid_shadow_schedule',
    'looker_content_aware_hybrid_shadow_schedule_summary',
    'schedule_change_application_preflight',
    'approved_schedule_changes_ready_to_apply',
    'looker_content_aware_proposal_preview',
    'looker_content_aware_proposal_preview_summary'
  )
  and relation.relkind = 'v';

create temporary table migration_030_function_snapshot
on commit drop
as
select
  function_record.oid,
  function_record.oid::regprocedure::text as function_identity,
  function_record.proowner,
  function_record.prokind,
  function_record.prosecdef,
  function_record.proconfig,
  pg_get_functiondef(function_record.oid) as function_definition
from pg_proc function_record
where function_record.oid in (
  to_regprocedure(
    'public.find_schedule_slot_conflicts(text,text,timestamptz,integer,uuid)'
  ),
  to_regprocedure(
    'public.get_schedule_reservation_capacity(text,text,timestamptz,text,uuid)'
  ),
  to_regprocedure(
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
  ),
  to_regprocedure(
    'public.create_content_aware_schedule_proposals(integer)'
  ),
  to_regprocedure(
    'public.refresh_schedule_proposals(date,integer)'
  )
);

create temporary table migration_030_target_column_snapshot
on commit drop
as
select
  column_record.table_name,
  column_record.ordinal_position,
  column_record.column_name,
  column_record.data_type,
  column_record.udt_schema,
  column_record.udt_name,
  column_record.is_nullable
from information_schema.columns column_record
where column_record.table_schema = 'public'
  and column_record.table_name in (
    'looker_content_aware_proposal_preview',
    'looker_content_aware_proposal_preview_summary'
  );

do $test$
declare
  v_contract text[];
  v_mismatch text;
begin
  if (select count(*) from migration_030_relation_snapshot) <> 7 then
    raise exception 'Migration 030 relation snapshot is incomplete';
  end if;

  if (select count(*) from migration_030_function_snapshot) <> 5 then
    raise exception 'Migration 030 function snapshot is incomplete';
  end if;

  if not exists (
    select 1 from migration_030_target_column_snapshot
  ) then
    raise exception 'Migration 030 target column snapshot is empty';
  end if;

  select array_agg(
    format('%s:%s:%s', column_name, data_type, udt_name)
    order by ordinal_position
  )
  into v_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if v_contract is distinct from array[
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
    raise exception 'Migration 030 initial Make contract changed: %',
      v_contract;
  end if;

  select string_agg(
    format('%s updatable=%s insertable=%s', table_name,
           is_updatable, is_insertable_into),
    '; ' order by table_name
  )
  into v_mismatch
  from information_schema.views
  where table_schema = 'public'
    and table_name in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and (is_updatable <> 'NO' or is_insertable_into <> 'NO');

  if v_mismatch is not null then
    raise exception 'Migration 030 target view is writable before test: %',
      v_mismatch;
  end if;

  if exists (
    select 1
    from pg_trigger trigger_record
    join pg_class relation
      on relation.oid = trigger_record.tgrelid
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'looker_content_aware_proposal_preview',
        'looker_content_aware_proposal_preview_summary'
      )
      and not trigger_record.tgisinternal
  ) then
    raise exception 'Migration 030 target has a user-defined trigger';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Reproduce the dirty service-role ACL
-- ---------------------------------------------------------------------------

grant all privileges on table
  public.looker_content_aware_proposal_preview,
  public.looker_content_aware_proposal_preview_summary
to service_role;

do $test$
declare
  v_mismatch text;
  v_other_contract text[];
  v_expected_other_contract text[];
begin
  with target_relations as (
    select relation.oid, relation.relname, relation.relowner,
           relation.relacl
    from pg_class relation
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relkind = 'v'
      and relation.relname in (
        'looker_content_aware_proposal_preview',
        'looker_content_aware_proposal_preview_summary'
      )
  ),
  available as (
    select
      target.relname,
      acl.privilege_type
    from target_relations target
    cross join lateral aclexplode(
      acldefault('r', target.relowner)
    ) acl
    where acl.grantee = target.relowner
  ),
  actual as (
    select
      target.relname,
      acl.privilege_type
    from target_relations target
    cross join lateral aclexplode(
      coalesce(target.relacl, acldefault('r', target.relowner))
    ) acl
    join pg_roles grantee
      on grantee.oid = acl.grantee
    where grantee.rolname = 'service_role'
  ),
  differences as (
    select
      coalesce(available.relname, actual.relname) as relname,
      coalesce(available.privilege_type, actual.privilege_type)
        as privilege_type,
      case
        when available.relname is null then 'unexpected'
        else 'missing'
      end as mismatch_kind
    from available
    full join actual
      on actual.relname = available.relname
     and actual.privilege_type = available.privilege_type
    where available.relname is null
       or actual.relname is null
  )
  select string_agg(
    format('%s:%s:%s', relname, privilege_type, mismatch_kind),
    '; ' order by relname, privilege_type
  )
  into v_mismatch
  from differences;

  if v_mismatch is not null then
    raise exception
      'Dirty service-role ACL does not contain every available privilege: %',
      v_mismatch;
  end if;

  if not exists (
    select 1
    from pg_class relation
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    cross join lateral aclexplode(
      coalesce(relation.relacl, acldefault('r', relation.relowner))
    ) acl
    join pg_roles grantee
      on grantee.oid = acl.grantee
    where namespace.nspname = 'public'
      and relation.relname in (
        'looker_content_aware_proposal_preview',
        'looker_content_aware_proposal_preview_summary'
      )
      and grantee.rolname = 'service_role'
      and acl.privilege_type <> 'SELECT'
  ) then
    raise exception 'Dirty service-role ACL has no non-SELECT privilege';
  end if;

  select array_agg(
    format(
      '%s:%s:%s:%s',
      relation.relname,
      coalesce(grantee.rolname, 'PUBLIC'),
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    )
    order by relation.relname, grantee.rolname,
             acl.privilege_type, acl.is_grantable
  )
  into v_other_contract
  from pg_class relation
  join pg_namespace namespace
    on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(
    coalesce(relation.relacl, acldefault('r', relation.relowner))
  ) acl
  left join pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'public'
    and relation.relkind = 'v'
    and relation.relname in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and acl.grantee <> relation.relowner
    and coalesce(grantee.rolname, 'PUBLIC') <> 'service_role';

  select array_agg(
    format('%s:%s:SELECT:NO', expected.view_name,
           'creator_dashboard_reader')
    order by expected.view_name
  )
  into v_expected_other_contract
  from (values
    ('looker_content_aware_proposal_preview'::text),
    ('looker_content_aware_proposal_preview_summary'::text)
  ) expected(view_name);

  if v_other_contract is distinct from v_expected_other_contract then
    raise exception
      'Dirty setup changed a non-service ACL: actual %, expected %',
      v_other_contract,
      v_expected_other_contract;
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 3. Apply migration 030's exact correction and assert the final ACL
-- ---------------------------------------------------------------------------

revoke all privileges on table
  public.looker_content_aware_proposal_preview,
  public.looker_content_aware_proposal_preview_summary
from service_role;

grant select on table
  public.looker_content_aware_proposal_preview,
  public.looker_content_aware_proposal_preview_summary
to service_role;

do $test$
declare
  v_actual_contract text[];
  v_expected_contract text[];
begin
  select array_agg(
    format(
      '%s:%s:%s:%s',
      relation.relname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    )
    order by
      relation.relname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      acl.is_grantable
  )
  into v_actual_contract
  from pg_class relation
  join pg_namespace namespace
    on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(
    coalesce(relation.relacl, acldefault('r', relation.relowner))
  ) acl
  left join pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'public'
    and relation.relkind = 'v'
    and relation.relname in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and acl.grantee <> relation.relowner;

  select array_agg(
    format('%s:%s:SELECT:NO', expected.view_name,
           expected.grantee_name)
    order by expected.view_name, expected.grantee_name
  )
  into v_expected_contract
  from (values
    ('looker_content_aware_proposal_preview'::text,
     'creator_dashboard_reader'::text),
    ('looker_content_aware_proposal_preview', 'service_role'),
    ('looker_content_aware_proposal_preview_summary',
     'creator_dashboard_reader'),
    ('looker_content_aware_proposal_preview_summary', 'service_role')
  ) expected(view_name, grantee_name);

  if v_actual_contract is distinct from v_expected_contract then
    raise exception
      'Migration 030 final ACL mismatch: actual %, expected %',
      v_actual_contract,
      v_expected_contract;
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 4. Prove object, reporting, and Make contracts did not change
-- ---------------------------------------------------------------------------

do $test$
declare
  v_mismatch text;
  v_contract text[];
begin
  with current_relations as (
    select
      relation.oid,
      relation.relname,
      relation.relkind,
      relation.relowner,
      relation.reloptions,
      pg_get_viewdef(relation.oid, true) as view_definition
    from pg_class relation
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'schedule_slot_reservations',
        'looker_content_aware_hybrid_shadow_schedule',
        'looker_content_aware_hybrid_shadow_schedule_summary',
        'schedule_change_application_preflight',
        'approved_schedule_changes_ready_to_apply',
        'looker_content_aware_proposal_preview',
        'looker_content_aware_proposal_preview_summary'
      )
      and relation.relkind = 'v'
  ),
  differences as (
    select
      coalesce(before.relname, after.relname) as relname
    from migration_030_relation_snapshot before
    full join current_relations after
      on after.relname = before.relname
    where before.oid is distinct from after.oid
       or before.relkind is distinct from after.relkind
       or before.relowner is distinct from after.relowner
       or before.reloptions is distinct from after.reloptions
       or before.view_definition is distinct from after.view_definition
  )
  select string_agg(relname, ', ' order by relname)
  into v_mismatch
  from differences;

  if v_mismatch is not null then
    raise exception 'Migration 030 changed relation metadata: %', v_mismatch;
  end if;

  with current_functions as (
    select
      function_record.oid,
      function_record.oid::regprocedure::text as function_identity,
      function_record.proowner,
      function_record.prokind,
      function_record.prosecdef,
      function_record.proconfig,
      pg_get_functiondef(function_record.oid) as function_definition
    from pg_proc function_record
    where function_record.oid in (
      to_regprocedure(
        'public.find_schedule_slot_conflicts(text,text,timestamptz,integer,uuid)'
      ),
      to_regprocedure(
        'public.get_schedule_reservation_capacity(text,text,timestamptz,text,uuid)'
      ),
      to_regprocedure(
        'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ),
      to_regprocedure(
        'public.create_content_aware_schedule_proposals(integer)'
      ),
      to_regprocedure(
        'public.refresh_schedule_proposals(date,integer)'
      )
    )
  ),
  differences as (
    select coalesce(before.function_identity, after.function_identity)
      as function_identity
    from migration_030_function_snapshot before
    full join current_functions after
      on after.function_identity = before.function_identity
    where before.oid is distinct from after.oid
       or before.proowner is distinct from after.proowner
       or before.prokind is distinct from after.prokind
       or before.prosecdef is distinct from after.prosecdef
       or before.proconfig is distinct from after.proconfig
       or before.function_definition is distinct from after.function_definition
  )
  select string_agg(function_identity, ', ' order by function_identity)
  into v_mismatch
  from differences;

  if v_mismatch is not null then
    raise exception 'Migration 030 changed scheduling functions: %',
      v_mismatch;
  end if;

  with current_columns as (
    select
      column_record.table_name,
      column_record.ordinal_position,
      column_record.column_name,
      column_record.data_type,
      column_record.udt_schema,
      column_record.udt_name,
      column_record.is_nullable
    from information_schema.columns column_record
    where column_record.table_schema = 'public'
      and column_record.table_name in (
        'looker_content_aware_proposal_preview',
        'looker_content_aware_proposal_preview_summary'
      )
  ),
  differences as (
    (
      select * from migration_030_target_column_snapshot
      except
      select * from current_columns
    )
    union all
    (
      select * from current_columns
      except
      select * from migration_030_target_column_snapshot
    )
  )
  select string_agg(
    format('%s[%s]:%s', table_name, ordinal_position, column_name),
    ', ' order by table_name, ordinal_position
  )
  into v_mismatch
  from differences;

  if v_mismatch is not null then
    raise exception 'Migration 030 changed target view columns: %', v_mismatch;
  end if;

  select array_agg(
    format('%s:%s:%s', column_name, data_type, udt_name)
    order by ordinal_position
  )
  into v_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if v_contract is distinct from array[
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
    raise exception 'Migration 030 final Make contract changed: %', v_contract;
  end if;

  select string_agg(
    format('%s updatable=%s insertable=%s', table_name,
           is_updatable, is_insertable_into),
    '; ' order by table_name
  )
  into v_mismatch
  from information_schema.views
  where table_schema = 'public'
    and table_name in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and (is_updatable <> 'NO' or is_insertable_into <> 'NO');

  if v_mismatch is not null then
    raise exception 'Migration 030 target view became writable: %', v_mismatch;
  end if;

  if exists (
    select 1
    from pg_trigger trigger_record
    join pg_class relation
      on relation.oid = trigger_record.tgrelid
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'looker_content_aware_proposal_preview',
        'looker_content_aware_proposal_preview_summary'
      )
      and not trigger_record.tgisinternal
  ) then
    raise exception 'Migration 030 added a user-defined trigger';
  end if;
end;
$test$;

rollback;
