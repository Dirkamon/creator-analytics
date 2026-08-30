-- Creator Analytics
-- Add the least-privilege Creator Analytics web read model
-- File: Database/033_add_creator_web_read_model.sql
--
-- This migration is additive. It creates an unexposed application schema,
-- projection-only views, a no-login view owner, and a restricted login role.
-- It does not change any existing public view, scheduling behavior, Make feed,
-- reporting grant, or production automation.

begin;


-- ---------------------------------------------------------------------------
-- 1. Roles and private schema
-- ---------------------------------------------------------------------------

do $migration_033_roles$
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_view_owner'
  ) then
    create role creator_analytics_web_view_owner
      nologin
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_reader'
  ) then
    create role creator_analytics_web_reader
      login
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls;
  end if;
end;
$migration_033_roles$;

alter role creator_analytics_web_view_owner
  nologin
  nosuperuser
  nocreatedb
  nocreaterole
  noinherit
  noreplication
  nobypassrls;

alter role creator_analytics_web_reader
  login
  nosuperuser
  nocreatedb
  nocreaterole
  noinherit
  noreplication
  nobypassrls;

alter role creator_analytics_web_reader
  set default_transaction_read_only = on;

alter role creator_analytics_web_reader
  set statement_timeout = '15s';

alter role creator_analytics_web_reader
  set idle_in_transaction_session_timeout = '15s';

alter role creator_analytics_web_reader
  set search_path = creator_app, pg_catalog;

create schema if not exists creator_app
  authorization creator_analytics_web_view_owner;

alter schema creator_app
  owner to creator_analytics_web_view_owner;

revoke all on schema creator_app
from public, anon, authenticated, service_role, creator_dashboard_reader;

revoke create on schema creator_app
from creator_analytics_web_reader;

grant connect on database postgres
to creator_analytics_web_reader;

grant usage on schema creator_app
to creator_analytics_web_reader;


-- ---------------------------------------------------------------------------
-- 2. Narrow source access for the no-login view owner
-- ---------------------------------------------------------------------------

grant usage on schema public
to creator_analytics_web_view_owner;

grant select on
  public.dashboard_posts,
  public.looker_dashboard_posts,
  public.looker_daily_growth,
  public.looker_posting_time_summary,
  public.looker_content_performance_summary,
  public.looker_schedule_change_proposals,
  public.pending_schedule_proposal_exports,
  public.looker_joint_posting_recommendations,
  public.looker_content_aware_fallback_preview,
  public.looker_scheduling_cadence_settings
to creator_analytics_web_view_owner;

-- The two queue views are SECURITY INVOKER, and migration 029 intentionally
-- keeps an exact ACL on the two public proposal-preview views. Private,
-- fixed-search-path functions owned by the existing database owner let the
-- application projections work without granting their owner base-table access
-- or changing any existing public-view ACL.
create function creator_app.read_unlabeled_posts_queue()
returns table (
  buffer_post_id text,
  platform text,
  channel_name text,
  status text,
  post_text text,
  external_link text,
  published_at_local timestamp without time zone,
  views bigint,
  latest_metric_date date
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    queue.buffer_post_id,
    queue.platform,
    queue.channel_name,
    queue.status,
    queue.post_text,
    queue.external_link,
    queue.published_at_local,
    queue.views,
    queue.latest_metric_date
  from public.unlabeled_posts_queue queue;
$function$;

create function creator_app.read_pending_label_queue_exports()
returns table (buffer_post_id text)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select queue.buffer_post_id
  from public.pending_label_queue_exports queue;
$function$;

create function creator_app.read_schedule_application_preflight()
returns table (
  proposal_id uuid,
  post_last_synced_at timestamp with time zone,
  blocking_reasons text[],
  is_ready boolean,
  platform text,
  proposed_due_at_utc timestamp with time zone
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    preflight.proposal_id,
    preflight.post_last_synced_at,
    preflight.blocking_reasons,
    preflight.is_ready,
    preflight.platform,
    preflight.proposed_due_at_utc
  from public.schedule_change_application_preflight preflight;
$function$;

create function creator_app.read_approved_schedule_changes()
returns table (proposal_id uuid)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select ready.proposal_id
  from public.approved_schedule_changes_ready_to_apply ready;
$function$;

create function creator_app.read_weekly_slot_plan()
returns table (
  platform text,
  content_format text,
  slot_rank integer,
  publish_day_name text,
  scheduled_hour_local integer,
  scheduled_time_local time without time zone,
  recommended_window text,
  recommendation_score numeric,
  confidence text,
  supporting_sample_size integer,
  metrics_status text,
  timezone_name text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    plan.platform,
    plan.content_format,
    plan.slot_rank,
    plan.publish_day_name,
    plan.scheduled_hour_local,
    plan.scheduled_time_local,
    plan.recommended_window,
    plan.recommendation_score,
    plan.confidence,
    plan.supporting_sample_size,
    plan.metrics_status,
    plan.timezone_name
  from public.looker_weekly_slot_plan plan;
$function$;

create function creator_app.read_proposal_preview_summary()
returns table (
  platform text,
  preview_rows integer,
  ready_to_create integer,
  blocked_rows integer,
  blocked_by_active_proposal integer,
  content_specific_rows integer,
  platform_overall_fallback_rows integer,
  guardrail_pass_rows integer,
  first_proposed_at_local timestamp without time zone,
  last_proposed_at_local timestamp without time zone,
  blocked_by_same_channel_reservation integer,
  blocked_by_channel_identity integer,
  blocked_by_configuration integer,
  blocked_by_daily_capacity integer,
  blocked_by_weekly_capacity integer
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    summary.platform,
    summary.preview_rows,
    summary.ready_to_create,
    summary.blocked_rows,
    summary.blocked_by_active_proposal,
    summary.content_specific_rows,
    summary.platform_overall_fallback_rows,
    summary.guardrail_pass_rows,
    summary.first_proposed_at_local,
    summary.last_proposed_at_local,
    summary.blocked_by_same_channel_reservation,
    summary.blocked_by_channel_identity,
    summary.blocked_by_configuration,
    summary.blocked_by_daily_capacity,
    summary.blocked_by_weekly_capacity
  from public.looker_content_aware_proposal_preview_summary summary;
$function$;

revoke all on function
  creator_app.read_approved_schedule_changes(),
  creator_app.read_unlabeled_posts_queue(),
  creator_app.read_pending_label_queue_exports(),
  creator_app.read_schedule_application_preflight(),
  creator_app.read_weekly_slot_plan(),
  creator_app.read_proposal_preview_summary()
from public, anon, authenticated, service_role, creator_dashboard_reader,
  creator_analytics_web_reader;

grant execute on function
  creator_app.read_approved_schedule_changes(),
  creator_app.read_unlabeled_posts_queue(),
  creator_app.read_pending_label_queue_exports(),
  creator_app.read_schedule_application_preflight(),
  creator_app.read_weekly_slot_plan(),
  creator_app.read_proposal_preview_summary()
to creator_analytics_web_view_owner, creator_analytics_web_reader;


-- ---------------------------------------------------------------------------
-- 3. Exact application projections
-- ---------------------------------------------------------------------------

create view creator_app.dashboard_posts
with (security_invoker = false, security_barrier = true)
as
select
  buffer_post_id,
  platform,
  channel_name,
  channel_display_name,
  status,
  post_text,
  external_link,
  due_at,
  label_status,
  internal_title,
  game,
  content_type,
  last_synced_at,
  latest_metric_captured_at
from public.dashboard_posts;

create view creator_app.looker_dashboard_posts
with (security_invoker = false, security_barrier = true)
as
select
  buffer_post_id,
  platform,
  channel_name,
  status,
  post_text,
  external_link,
  published_at_utc,
  label_status,
  clip_group,
  game,
  content_type,
  latest_metric_date,
  views,
  reactions,
  comments,
  shares,
  saves,
  calculated_interaction_rate
from public.looker_dashboard_posts;

create view creator_app.looker_daily_growth
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  captured_on,
  views_gained,
  reactions_gained,
  comments_gained,
  shares_gained
from public.looker_daily_growth;

create view creator_app.looker_posting_time_summary
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  channel_name,
  publish_day_name,
  publish_hour,
  post_count,
  average_views,
  median_views,
  average_calculated_interaction_rate
from public.looker_posting_time_summary;

create view creator_app.looker_content_performance_summary
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  game,
  content_type,
  vibe,
  hook_type,
  post_count,
  average_views,
  median_views,
  average_calculated_interaction_rate
from public.looker_content_performance_summary;

create view creator_app.looker_schedule_change_proposals
with (security_invoker = false, security_barrier = true)
as
select
  proposal_id,
  buffer_post_id,
  platform,
  content_format,
  post_text,
  external_link,
  current_due_at_utc,
  proposed_due_at_utc,
  slot_rank,
  source_recommendation_rank,
  recommendation_score,
  confidence,
  supporting_sample_size,
  metrics_status,
  timezone_name,
  approval_status,
  approved_at,
  applied_at,
  generated_at,
  updated_at
from public.looker_schedule_change_proposals;

create view creator_app.unlabeled_posts_queue
with (security_invoker = false, security_barrier = true)
as
select
  buffer_post_id,
  platform,
  channel_name,
  status,
  post_text,
  external_link,
  published_at_local,
  views,
  latest_metric_date
from creator_app.read_unlabeled_posts_queue();

create view creator_app.pending_label_queue_exports
with (security_invoker = false, security_barrier = true)
as
select buffer_post_id
from creator_app.read_pending_label_queue_exports();

create view creator_app.pending_schedule_proposal_exports
with (security_invoker = false, security_barrier = true)
as
select proposal_id
from public.pending_schedule_proposal_exports;

create view creator_app.schedule_change_application_preflight
with (security_invoker = false, security_barrier = true)
as
select
  proposal_id,
  post_last_synced_at,
  blocking_reasons,
  is_ready,
  platform,
  proposed_due_at_utc
from creator_app.read_schedule_application_preflight();

create view creator_app.approved_schedule_changes_ready_to_apply
with (security_invoker = false, security_barrier = true)
as
select proposal_id
from creator_app.read_approved_schedule_changes();

create view creator_app.looker_joint_posting_recommendations
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  recommendation_rank,
  recommended_slot,
  post_count,
  platform_post_count,
  avg_views,
  median_views,
  recommendation_score,
  confidence,
  latest_metric_date,
  metrics_age_days,
  metrics_status,
  recommendation_ready_for_approval_mode
from public.looker_joint_posting_recommendations;

create view creator_app.looker_content_aware_fallback_preview
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  game,
  content_type,
  vibe,
  selected_model_level,
  selected_model_priority,
  group_sample_size,
  minimum_sample_size,
  recommended_slot,
  recommendation_score,
  confidence,
  metrics_status,
  recommendation_ready_for_preview,
  fallback_reason
from public.looker_content_aware_fallback_preview;

create view creator_app.looker_scheduling_cadence_settings
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  content_format,
  posts_per_week,
  max_posts_per_day,
  min_gap_hours,
  protected_hours,
  minimum_sample_size,
  metrics_freshness_limit_days,
  timezone_name,
  is_active,
  updated_at
from public.looker_scheduling_cadence_settings;

create view creator_app.looker_weekly_slot_plan
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  content_format,
  slot_rank,
  publish_day_name,
  scheduled_hour_local,
  scheduled_time_local,
  recommended_window,
  recommendation_score,
  confidence,
  supporting_sample_size,
  metrics_status,
  timezone_name
from creator_app.read_weekly_slot_plan();

create view creator_app.looker_content_aware_proposal_preview_summary
with (security_invoker = false, security_barrier = true)
as
select
  platform,
  preview_rows,
  ready_to_create,
  blocked_rows,
  blocked_by_active_proposal,
  content_specific_rows,
  platform_overall_fallback_rows,
  guardrail_pass_rows,
  first_proposed_at_local,
  last_proposed_at_local,
  blocked_by_same_channel_reservation,
  blocked_by_channel_identity,
  blocked_by_configuration,
  blocked_by_daily_capacity,
  blocked_by_weekly_capacity
from creator_app.read_proposal_preview_summary();

alter view creator_app.dashboard_posts
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_dashboard_posts
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_daily_growth
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_posting_time_summary
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_content_performance_summary
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_schedule_change_proposals
  owner to creator_analytics_web_view_owner;
alter view creator_app.unlabeled_posts_queue
  owner to creator_analytics_web_view_owner;
alter view creator_app.pending_label_queue_exports
  owner to creator_analytics_web_view_owner;
alter view creator_app.pending_schedule_proposal_exports
  owner to creator_analytics_web_view_owner;
alter view creator_app.schedule_change_application_preflight
  owner to creator_analytics_web_view_owner;
alter view creator_app.approved_schedule_changes_ready_to_apply
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_joint_posting_recommendations
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_content_aware_fallback_preview
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_scheduling_cadence_settings
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_weekly_slot_plan
  owner to creator_analytics_web_view_owner;
alter view creator_app.looker_content_aware_proposal_preview_summary
  owner to creator_analytics_web_view_owner;

revoke all privileges on all tables in schema creator_app
from
  public,
  anon,
  authenticated,
  service_role,
  creator_dashboard_reader,
  creator_analytics_web_reader;

grant select on all tables in schema creator_app
to creator_analytics_web_reader;

alter default privileges
for role creator_analytics_web_view_owner
in schema creator_app
revoke all privileges on tables from public;

comment on schema creator_app is
'Unexposed, server-only Creator Analytics web read model. Browser roles receive no schema access.';

comment on role creator_analytics_web_reader is
'Restricted server-only login for creator_app projection reads and exact private helper execution. Passwords are provisioned outside migrations.';

comment on role creator_analytics_web_view_owner is
'No-login owner for creator_app projection views; receives only narrow source read access.';


-- ---------------------------------------------------------------------------
-- 4. Fail-closed postconditions and compatibility guards
-- ---------------------------------------------------------------------------

do $migration_033_postconditions$
declare
  v_actual_acl text[];
  v_expected_acl text[];
  v_make_contract text[];
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
    raise exception using
      errcode = '42501',
      message = 'Migration 033 view-owner attributes are not fail-closed';
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
    raise exception using
      errcode = '42501',
      message = 'Migration 033 reader attributes are not fail-closed';
  end if;

  select string_agg(relation.relname, ', ' order by relation.relname)
  into v_mismatch
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  where namespace.nspname = 'creator_app'
    and relation.relkind = 'v'
    and (
      pg_catalog.pg_get_userbyid(relation.relowner)
        <> 'creator_analytics_web_view_owner'
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
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 033 application view ownership/options mismatch: %s',
        v_mismatch
      );
  end if;

  if (
    select count(*)
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'creator_app'
      and relation.relkind = 'v'
  ) <> 16 then
    raise exception using
      errcode = '42P01',
      message = 'Migration 033 must create exactly 16 application views';
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
    raise exception using
      errcode = '42501',
      message = 'Migration 033 private preview helper is not fail-closed';
  end if;

  select array_agg(
    format(
      '%s:%s:%s',
      function_record.proname,
      coalesce(grantee.rolname, 'PUBLIC'),
      acl.privilege_type
    ) order by function_record.proname, grantee.rolname, acl.privilege_type
  )
  into v_actual_acl
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

  if v_actual_acl is distinct from array[
    'read_approved_schedule_changes:creator_analytics_web_reader:EXECUTE',
    'read_approved_schedule_changes:creator_analytics_web_view_owner:EXECUTE',
    'read_pending_label_queue_exports:creator_analytics_web_reader:EXECUTE',
    'read_pending_label_queue_exports:creator_analytics_web_view_owner:EXECUTE',
    'read_proposal_preview_summary:creator_analytics_web_reader:EXECUTE',
    'read_proposal_preview_summary:creator_analytics_web_view_owner:EXECUTE',
    'read_schedule_application_preflight:creator_analytics_web_reader:EXECUTE',
    'read_schedule_application_preflight:creator_analytics_web_view_owner:EXECUTE',
    'read_unlabeled_posts_queue:creator_analytics_web_reader:EXECUTE',
    'read_unlabeled_posts_queue:creator_analytics_web_view_owner:EXECUTE',
    'read_weekly_slot_plan:creator_analytics_web_reader:EXECUTE',
    'read_weekly_slot_plan:creator_analytics_web_view_owner:EXECUTE'
  ]::text[] then
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 033 private preview helper ACL mismatch: %s',
        coalesce(v_actual_acl::text, 'NULL')
      );
  end if;

  select array_agg(
    format(
      '%s:%s:%s',
      relation.relname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type
    )
    order by relation.relname, grantee.rolname, acl.privilege_type
  )
  into v_actual_acl
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
    format('%s:creator_analytics_web_reader:SELECT', relation.relname)
    order by relation.relname
  )
  into v_expected_acl
  from pg_catalog.pg_class relation
  join pg_catalog.pg_namespace namespace
    on namespace.oid = relation.relnamespace
  where namespace.nspname = 'creator_app'
    and relation.relkind = 'v';

  if v_actual_acl is distinct from v_expected_acl then
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 033 application ACL mismatch: actual %s; expected %s',
        coalesce(v_actual_acl::text, 'NULL'),
        v_expected_acl::text
      );
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
    raise exception using
      errcode = '42501',
      message = 'Migration 033 changed posts RLS behavior or source access';
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
    raise exception using
      errcode = '42P16',
      message = format(
        'Migration 033 changed the Make-facing 19-column contract: %s',
        v_make_contract::text
      );
  end if;
end;
$migration_033_postconditions$;

commit;
