-- Creator Analytics
-- Regression coverage for migration 033
-- File: Tests/Database/033_add_creator_web_read_model_regression.sql
--
-- Run against an isolated PostgreSQL/Supabase-compatible database after
-- migrations 001-033. The script validates the exact private read model,
-- browser denial, reporting/Make compatibility, and read-only behavior. It
-- makes no persistent changes and ends in ROLLBACK.

begin;

set local timezone = 'UTC';
set local statement_timeout = '2min';
set local lock_timeout = '10s';


-- ---------------------------------------------------------------------------
-- 0. Hosted Supabase non-superuser CREATEROLE compatibility
-- ---------------------------------------------------------------------------

-- Exercise the migration's role-management and ownership-handoff pattern from
-- a role whose only privileged role attribute is CREATEROLE. The surrounding
-- transaction rolls back every probe role, membership, and schema.
create role migration_033_hosted_admin
  nologin
  nosuperuser
  nocreatedb
  createrole
  noinherit
  noreplication
  nobypassrls;

grant migration_033_hosted_admin
to current_user
with set true, inherit false;

-- Schema creation is a database privilege, not a role attribute. Hosted
-- migration administrators have it without CREATEDB; grant only that scoped
-- privilege to the disposable probe role.
grant create on database postgres
to migration_033_hosted_admin;

set local role migration_033_hosted_admin;

create role migration_033_hosted_view_owner
  nologin
  nosuperuser
  nocreatedb
  nocreaterole
  noinherit
  noreplication
  nobypassrls;

create role migration_033_hosted_reader
  login
  nosuperuser
  nocreatedb
  nocreaterole
  noinherit
  noreplication
  nobypassrls;

-- Hosted-compatible normalization deliberately avoids SUPERUSER, CREATEDB,
-- CREATEROLE, REPLICATION, and BYPASSRLS ALTER options.
alter role migration_033_hosted_view_owner
  nologin
  noinherit;

alter role migration_033_hosted_reader
  login
  noinherit;

grant migration_033_hosted_view_owner
to current_user
with set true, inherit false;

create schema migration_033_hosted_probe
  authorization current_user;

grant usage, create on schema migration_033_hosted_probe
to migration_033_hosted_view_owner;

alter schema migration_033_hosted_probe
  owner to migration_033_hosted_view_owner;

revoke migration_033_hosted_view_owner
from current_user
granted by current_user;

do $test$
declare
  v_mismatch text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = current_user
      and not rolsuper
      and not rolcreatedb
      and rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
  ) then
    raise exception
      'Migration 033 hosted-compat probe did not use minimum CREATEROLE administration';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_roles
    where (
      rolname = 'migration_033_hosted_view_owner'
      and not rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
    ) or (
      rolname = 'migration_033_hosted_reader'
      and rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
    )
  ) <> 2 then
    raise exception 'Migration 033 hosted-compat role attributes are unsafe';
  end if;

  select string_agg(
    format(
      '%s->%s (admin=%s, inherit=%s, set=%s)',
      member_role.rolname,
      granted_role.rolname,
      membership.admin_option,
      membership.inherit_option,
      membership.set_option
    ),
    ', ' order by granted_role.rolname, member_role.rolname
  )
  into v_mismatch
  from pg_catalog.pg_auth_members membership
  join pg_catalog.pg_roles granted_role
    on granted_role.oid = membership.roleid
  join pg_catalog.pg_roles member_role
    on member_role.oid = membership.member
  where (
      member_role.rolname in (
        'migration_033_hosted_view_owner',
        'migration_033_hosted_reader'
      )
    )
    or (
      granted_role.rolname in (
        'migration_033_hosted_view_owner',
        'migration_033_hosted_reader'
      )
      and not (
        member_role.rolname = current_user
        and membership.admin_option
        and not membership.inherit_option
        and not membership.set_option
      )
    );

  if v_mismatch is not null then
    raise exception
      'Migration 033 hosted-compat membership mismatch: %',
      v_mismatch;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_namespace namespace
    where namespace.nspname = 'migration_033_hosted_probe'
      and pg_catalog.pg_get_userbyid(namespace.nspowner) =
        'migration_033_hosted_view_owner'
  ) then
    raise exception 'Migration 033 hosted-compat ownership handoff failed';
  end if;
end;
$test$;

reset role;

revoke migration_033_hosted_admin
from current_user
granted by current_user;


-- ---------------------------------------------------------------------------
-- 1. Exact roles, settings, schema, views, columns, owners, and options
-- ---------------------------------------------------------------------------

do $test$
declare
  v_settings text[];
  v_mismatch text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_view_owner'
      and not rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
  ) then
    raise exception 'Migration 033 view-owner attributes are incorrect';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_reader'
      and rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
  ) then
    raise exception 'Migration 033 reader attributes are incorrect';
  end if;

  select string_agg(
    format(
      '%s->%s (admin=%s, inherit=%s, set=%s)',
      member_role.rolname,
      granted_role.rolname,
      membership.admin_option,
      membership.inherit_option,
      membership.set_option
    ),
    ', ' order by granted_role.rolname, member_role.rolname
  )
  into v_mismatch
  from pg_catalog.pg_auth_members membership
  join pg_catalog.pg_roles granted_role
    on granted_role.oid = membership.roleid
  join pg_catalog.pg_roles member_role
    on member_role.oid = membership.member
  where (
      member_role.rolname in (
        'creator_analytics_web_view_owner',
        'creator_analytics_web_reader'
      )
    )
    or (
      granted_role.rolname in (
        'creator_analytics_web_view_owner',
        'creator_analytics_web_reader'
      )
      and not (
        member_role.rolname = current_user
        and membership.admin_option
        and not membership.inherit_option
        and not membership.set_option
      )
    );

  if v_mismatch is not null then
    raise exception 'Migration 033 application role membership mismatch: %',
      v_mismatch;
  end if;

  select rolconfig
  into v_settings
  from pg_catalog.pg_roles
  where rolname = 'creator_analytics_web_reader';

  if not v_settings @> array[
    'default_transaction_read_only=on',
    'statement_timeout=15s',
    'idle_in_transaction_session_timeout=15s',
    'search_path=creator_app, pg_catalog'
  ]::text[] then
    raise exception 'Migration 033 reader settings are incomplete: %',
      v_settings;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_namespace namespace
    where namespace.nspname = 'creator_app'
      and pg_catalog.pg_get_userbyid(namespace.nspowner) =
        'creator_analytics_web_view_owner'
  ) then
    raise exception 'Migration 033 creator_app schema owner is incorrect';
  end if;

  select string_agg(relation.relname, ', ' order by relation.relname)
  into v_mismatch
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  where namespace.nspname = 'creator_app'
    and relation.relkind = 'v'
    and (
      pg_catalog.pg_get_userbyid(relation.relowner) <>
        'creator_analytics_web_view_owner'
      or not coalesce(
        relation.reloptions @> array['security_barrier=true']::text[],
        false
      )
      or not coalesce(
        relation.reloptions @> array['security_invoker=false']::text[],
        false
      )
    );

  if v_mismatch is not null then
    raise exception 'Migration 033 view owner/options mismatch: %', v_mismatch;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc function_record
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_record.pronamespace
    where namespace.nspname = 'creator_app'
      and function_record.proname in (
        'read_approved_schedule_changes',
        'read_unlabeled_posts_queue',
        'read_pending_label_queue_exports',
        'read_schedule_application_preflight',
        'read_weekly_slot_plan',
        'read_proposal_preview_summary'
      )
      and function_record.prosecdef
      and function_record.provolatile = 's'
      and pg_catalog.pg_get_userbyid(function_record.proowner) = 'postgres'
      and function_record.proconfig @> array[
        'search_path=pg_catalog, public'
      ]::text[]
    having count(*) = 6
  ) then
    raise exception 'Migration 033 private preview helper is not fail-closed';
  end if;
end;
$test$;

create temporary table migration_033_expected_columns (
  view_name text primary key,
  column_names text[] not null
) on commit drop;

insert into migration_033_expected_columns (view_name, column_names)
values
  ('dashboard_posts', array[
    'buffer_post_id', 'platform', 'channel_name', 'channel_display_name',
    'status', 'post_text', 'external_link', 'due_at', 'label_status',
    'internal_title', 'game', 'content_type', 'last_synced_at',
    'latest_metric_captured_at'
  ]),
  ('looker_dashboard_posts', array[
    'buffer_post_id', 'platform', 'channel_name', 'status', 'post_text',
    'external_link', 'published_at_utc', 'label_status', 'clip_group', 'game',
    'content_type', 'latest_metric_date', 'views', 'reactions', 'comments',
    'shares', 'saves', 'calculated_interaction_rate'
  ]),
  ('looker_daily_growth', array[
    'platform', 'captured_on', 'views_gained', 'reactions_gained',
    'comments_gained', 'shares_gained'
  ]),
  ('looker_posting_time_summary', array[
    'platform', 'channel_name', 'publish_day_name', 'publish_hour',
    'post_count', 'average_views', 'median_views',
    'average_calculated_interaction_rate'
  ]),
  ('looker_content_performance_summary', array[
    'platform', 'game', 'content_type', 'vibe', 'hook_type', 'post_count',
    'average_views', 'median_views', 'average_calculated_interaction_rate'
  ]),
  ('looker_schedule_change_proposals', array[
    'proposal_id', 'buffer_post_id', 'platform', 'content_format',
    'post_text', 'external_link', 'current_due_at_utc',
    'proposed_due_at_utc', 'slot_rank', 'source_recommendation_rank',
    'recommendation_score', 'confidence', 'supporting_sample_size',
    'metrics_status', 'timezone_name', 'approval_status', 'approved_at',
    'applied_at', 'generated_at', 'updated_at'
  ]),
  ('unlabeled_posts_queue', array[
    'buffer_post_id', 'platform', 'channel_name', 'status', 'post_text',
    'external_link', 'published_at_local', 'views', 'latest_metric_date'
  ]),
  ('pending_label_queue_exports', array['buffer_post_id']),
  ('pending_schedule_proposal_exports', array['proposal_id']),
  ('schedule_change_application_preflight', array[
    'proposal_id', 'post_last_synced_at', 'blocking_reasons', 'is_ready',
    'platform', 'proposed_due_at_utc'
  ]),
  ('approved_schedule_changes_ready_to_apply', array['proposal_id']),
  ('looker_joint_posting_recommendations', array[
    'platform', 'recommendation_rank', 'recommended_slot', 'post_count',
    'platform_post_count', 'avg_views', 'median_views',
    'recommendation_score', 'confidence', 'latest_metric_date',
    'metrics_age_days', 'metrics_status',
    'recommendation_ready_for_approval_mode'
  ]),
  ('looker_content_aware_fallback_preview', array[
    'platform', 'game', 'content_type', 'vibe', 'selected_model_level',
    'selected_model_priority', 'group_sample_size', 'minimum_sample_size',
    'recommended_slot', 'recommendation_score', 'confidence',
    'metrics_status', 'recommendation_ready_for_preview', 'fallback_reason'
  ]),
  ('looker_scheduling_cadence_settings', array[
    'platform', 'content_format', 'posts_per_week', 'max_posts_per_day',
    'min_gap_hours', 'protected_hours', 'minimum_sample_size',
    'metrics_freshness_limit_days', 'timezone_name', 'is_active', 'updated_at'
  ]),
  ('looker_weekly_slot_plan', array[
    'platform', 'content_format', 'slot_rank', 'publish_day_name',
    'scheduled_hour_local', 'scheduled_time_local', 'recommended_window',
    'recommendation_score', 'confidence', 'supporting_sample_size',
    'metrics_status', 'timezone_name'
  ]),
  ('looker_content_aware_proposal_preview_summary', array[
    'platform', 'preview_rows', 'ready_to_create', 'blocked_rows',
    'blocked_by_active_proposal', 'content_specific_rows',
    'platform_overall_fallback_rows', 'guardrail_pass_rows',
    'first_proposed_at_local', 'last_proposed_at_local',
    'blocked_by_same_channel_reservation', 'blocked_by_channel_identity',
    'blocked_by_configuration', 'blocked_by_daily_capacity',
    'blocked_by_weekly_capacity'
  ]);

do $test$
declare
  v_mismatch text;
begin
  if (select count(*) from migration_033_expected_columns) <> 16 then
    raise exception 'Migration 033 expected view inventory is incomplete';
  end if;

  select string_agg(expected.view_name, ', ' order by expected.view_name)
  into v_mismatch
  from migration_033_expected_columns expected
  left join lateral (
    select array_agg(attribute.attname::text order by attribute.attnum)
      as column_names
    from pg_catalog.pg_namespace namespace
    join pg_catalog.pg_class relation
      on relation.relnamespace = namespace.oid
    join pg_catalog.pg_attribute attribute
      on attribute.attrelid = relation.oid
     and attribute.attnum > 0
     and not attribute.attisdropped
    where namespace.nspname = 'creator_app'
      and relation.relname = expected.view_name
  ) actual on true
  where actual.column_names is distinct from expected.column_names;

  if v_mismatch is not null then
    raise exception 'Migration 033 projection column mismatch: %', v_mismatch;
  end if;

  select string_agg(
    format('%s.%s', app_relation.relname, app_attribute.attname),
    ', ' order by app_relation.relname, app_attribute.attnum
  )
  into v_mismatch
  from pg_catalog.pg_namespace app_namespace
  join pg_catalog.pg_class app_relation
    on app_relation.relnamespace = app_namespace.oid
  join pg_catalog.pg_attribute app_attribute
    on app_attribute.attrelid = app_relation.oid
   and app_attribute.attnum > 0
   and not app_attribute.attisdropped
  left join pg_catalog.pg_namespace source_namespace
    on source_namespace.nspname = 'public'
  left join pg_catalog.pg_class source_relation
    on source_relation.relnamespace = source_namespace.oid
   and source_relation.relname = app_relation.relname
  left join pg_catalog.pg_attribute source_attribute
    on source_attribute.attrelid = source_relation.oid
   and source_attribute.attname = app_attribute.attname
   and source_attribute.attnum > 0
   and not source_attribute.attisdropped
  where app_namespace.nspname = 'creator_app'
    and (
      source_attribute.attname is null
      or app_attribute.atttypid is distinct from source_attribute.atttypid
      or app_attribute.atttypmod is distinct from source_attribute.atttypmod
    );

  if v_mismatch is not null then
    raise exception 'Migration 033 source/application type mismatch: %',
      v_mismatch;
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Exact ACL, browser denial, source isolation, and RLS policy
-- ---------------------------------------------------------------------------

do $test$
declare
  v_actual text[];
  v_expected text[];
  v_mismatch text;
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
    ) order by relation.relname, grantee.rolname, acl.privilege_type
  )
  into v_actual
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(
    coalesce(relation.relacl, acldefault('r', relation.relowner))
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'creator_app'
    and relation.relkind = 'v'
    and acl.grantee <> relation.relowner;

  select array_agg(
    format(
      '%s:creator_analytics_web_reader:SELECT:NO',
      expected.view_name
    ) order by expected.view_name
  )
  into v_expected
  from migration_033_expected_columns expected;

  if v_actual is distinct from v_expected then
    raise exception 'Migration 033 direct app ACL mismatch: actual %, expected %',
      v_actual, v_expected;
  end if;

  select array_agg(
    format(
      '%s:%s:%s:%s',
      function_record.proname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    ) order by function_record.proname, grantee.rolname, acl.privilege_type
  )
  into v_actual
  from pg_catalog.pg_proc function_record
  join pg_catalog.pg_namespace namespace
    on namespace.oid = function_record.pronamespace
  cross join lateral aclexplode(
    coalesce(function_record.proacl, acldefault('f', function_record.proowner))
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'creator_app'
    and function_record.proname in (
      'read_approved_schedule_changes',
      'read_unlabeled_posts_queue',
      'read_pending_label_queue_exports',
      'read_schedule_application_preflight',
      'read_weekly_slot_plan',
      'read_proposal_preview_summary'
    )
    and acl.grantee <> function_record.proowner;

  if v_actual is distinct from array[
    'read_approved_schedule_changes:creator_analytics_web_reader:EXECUTE:NO',
    'read_approved_schedule_changes:creator_analytics_web_view_owner:EXECUTE:NO',
    'read_pending_label_queue_exports:creator_analytics_web_reader:EXECUTE:NO',
    'read_pending_label_queue_exports:creator_analytics_web_view_owner:EXECUTE:NO',
    'read_proposal_preview_summary:creator_analytics_web_reader:EXECUTE:NO',
    'read_proposal_preview_summary:creator_analytics_web_view_owner:EXECUTE:NO',
    'read_schedule_application_preflight:creator_analytics_web_reader:EXECUTE:NO',
    'read_schedule_application_preflight:creator_analytics_web_view_owner:EXECUTE:NO',
    'read_unlabeled_posts_queue:creator_analytics_web_reader:EXECUTE:NO',
    'read_unlabeled_posts_queue:creator_analytics_web_view_owner:EXECUTE:NO',
    'read_weekly_slot_plan:creator_analytics_web_reader:EXECUTE:NO',
    'read_weekly_slot_plan:creator_analytics_web_view_owner:EXECUTE:NO'
  ]::text[] then
    raise exception 'Migration 033 private helper ACL mismatch: %', v_actual;
  end if;

  select string_agg(
    format(
      '%s:%s',
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type
    ), ', ' order by grantee.rolname, acl.privilege_type
  )
  into v_mismatch
  from pg_catalog.pg_namespace namespace
  cross join lateral aclexplode(
    coalesce(namespace.nspacl, acldefault('n', namespace.nspowner))
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'creator_app'
    and acl.grantee <> namespace.nspowner
    and not (
      grantee.rolname = 'creator_analytics_web_reader'
      and acl.privilege_type = 'USAGE'
      and not acl.is_grantable
    );

  if v_mismatch is not null then
    raise exception 'Migration 033 unexpected schema privilege: %', v_mismatch;
  end if;

  if exists (
    select 1
    from (values
      ('anon'::text),
      ('authenticated'::text),
      ('service_role'::text),
      ('creator_dashboard_reader'::text)
    ) denied(role_name)
    where pg_catalog.has_schema_privilege(
      denied.role_name,
      'creator_app',
      'USAGE'
    )
  ) then
    raise exception 'Migration 033 exposed creator_app schema to a denied role';
  end if;

  if exists (
    select 1
    from migration_033_expected_columns expected
    join pg_catalog.pg_namespace app_namespace
      on app_namespace.nspname = 'creator_app'
    join pg_catalog.pg_class app_relation
      on app_relation.relnamespace = app_namespace.oid
     and app_relation.relname = expected.view_name
    cross join (values
      ('anon'::text),
      ('authenticated'::text),
      ('service_role'::text),
      ('creator_dashboard_reader'::text)
    ) denied(role_name)
    where pg_catalog.has_any_column_privilege(
      denied.role_name,
      app_relation.oid,
      'SELECT'
    )
  ) then
    raise exception 'Migration 033 exposed an app view to a denied role';
  end if;

  if exists (
    select 1
    from migration_033_expected_columns expected
    join pg_catalog.pg_namespace source_namespace
      on source_namespace.nspname = 'public'
    join pg_catalog.pg_class source_relation
      on source_relation.relnamespace = source_namespace.oid
     and source_relation.relname = expected.view_name
    where pg_catalog.has_any_column_privilege(
      'creator_analytics_web_reader',
      source_relation.oid,
      'SELECT'
    )
  ) then
    raise exception 'Migration 033 reader can query a public source view';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policy policy_record
    join pg_catalog.pg_class relation
      on relation.oid = policy_record.polrelid
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname = 'posts'
  ) or pg_catalog.has_any_column_privilege(
    'creator_analytics_web_view_owner',
    'public.posts',
    'SELECT'
  ) then
    raise exception 'Migration 033 changed posts RLS behavior or source access';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 3. Reader query success and write/function denial
-- ---------------------------------------------------------------------------

grant creator_analytics_web_reader
to current_user
with set true, inherit false;

set local role creator_analytics_web_reader;

select count(*) from creator_app.dashboard_posts;
select count(*) from creator_app.looker_dashboard_posts;
select count(*) from creator_app.looker_daily_growth;
select count(*) from creator_app.looker_posting_time_summary;
select count(*) from creator_app.looker_content_performance_summary;
select count(*) from creator_app.looker_schedule_change_proposals;
select count(*) from creator_app.unlabeled_posts_queue;
select count(*) from creator_app.pending_label_queue_exports;
select count(*) from creator_app.pending_schedule_proposal_exports;
select count(*) from creator_app.schedule_change_application_preflight;
select count(*) from creator_app.approved_schedule_changes_ready_to_apply;
select count(*) from creator_app.looker_joint_posting_recommendations;
select count(*) from creator_app.looker_content_aware_fallback_preview;
select count(*) from creator_app.looker_scheduling_cadence_settings;
select count(*) from creator_app.looker_weekly_slot_plan;
select count(*)
from creator_app.looker_content_aware_proposal_preview_summary;

reset role;

revoke creator_analytics_web_reader
from current_user
granted by current_user;

do $test$
declare
  v_unexpected text;
begin
  if pg_catalog.has_table_privilege(
       'creator_analytics_web_reader',
       (
         select relation.oid
         from pg_catalog.pg_class relation
         join pg_catalog.pg_namespace namespace
           on namespace.oid = relation.relnamespace
         where namespace.nspname = 'creator_app'
           and relation.relname = 'dashboard_posts'
       ),
       'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     ) then
    raise exception 'Migration 033 reader received a write-like privilege';
  end if;

  select string_agg(function_record.oid::regprocedure::text, ', ')
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
      'mark_label_queue_exported',
      'refresh_schedule_proposals',
      'create_content_aware_schedule_proposals',
      'set_schedule_proposal_decision',
      'mark_schedule_proposal_exported',
      'mark_schedule_proposal_applied',
      'mark_schedule_proposal_error'
    )
    and pg_catalog.has_function_privilege(
      'creator_analytics_web_reader',
      function_record.oid,
      'EXECUTE'
    );

  if v_unexpected is not null then
    raise exception 'Migration 033 reader can execute mutation functions: %',
      v_unexpected;
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 4. Existing reporting, scheduling, RLS, and Make contracts remain intact
-- ---------------------------------------------------------------------------

do $test$
declare
  v_make_contract text[];
  v_missing text;
begin
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
    raise exception 'Migration 033 changed the Make contract: %',
      v_make_contract;
  end if;

  if not pg_catalog.has_table_privilege(
       'service_role',
       'public.approved_schedule_changes_ready_to_apply',
       'SELECT'
     ) then
    raise exception 'Migration 033 removed the Make service-role grant';
  end if;

  select string_agg(expected.view_name, ', ' order by expected.view_name)
  into v_missing
  from (values
    ('looker_dashboard_posts'::text),
    ('looker_daily_growth'::text),
    ('looker_posting_time_summary'::text),
    ('looker_content_performance_summary'::text),
    ('looker_schedule_change_proposals'::text),
    ('pending_schedule_proposal_exports'::text),
    ('looker_joint_posting_recommendations'::text),
    ('looker_content_aware_fallback_preview'::text),
    ('looker_scheduling_cadence_settings'::text),
    ('looker_weekly_slot_plan'::text),
    ('looker_content_aware_proposal_preview_summary'::text)
  ) expected(view_name)
  where not pg_catalog.has_table_privilege(
    'creator_dashboard_reader',
    format('public.%I', expected.view_name),
    'SELECT'
  );

  if v_missing is not null then
    raise exception 'Migration 033 removed reporting-reader access: %',
      v_missing;
  end if;

  if to_regprocedure(
       'public.create_collision_safe_schedule_proposals(integer,date,date)'
     ) is null
     or to_regprocedure(
       'public.refresh_schedule_proposals(date,integer)'
     ) is null
     or to_regclass('public.schedule_slot_reservations') is null
     or to_regclass('public.schedule_change_application_preflight') is null then
    raise exception 'Migration 033 changed a migration 029-032 object';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'public'
      and relation.relname in (
        'organizations',
        'channels',
        'content_items',
        'posts',
        'post_metric_snapshots',
        'schedule_recommendations',
        'automation_runs',
        'scheduling_cadence_settings',
        'schedule_change_proposals'
      )
      and relation.relrowsecurity
  ) <> 9 then
    raise exception 'Migration 033 changed existing RLS enablement';
  end if;
end;
$test$;


-- The regression must never persist fixtures or permission mutations.
rollback;
