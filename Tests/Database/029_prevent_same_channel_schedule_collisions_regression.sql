-- Creator Analytics
-- Regression coverage for migration 029
-- File: Tests/Database/029_prevent_same_channel_schedule_collisions_regression.sql
--
-- Run only against an isolated PostgreSQL/Supabase-compatible test database
-- after migrations 001-029. Scheduler fixtures derive from one transaction-
-- scoped America/Denver date. The observed 2026-08-24 collision is preserved
-- separately as a deterministic reservation test. Every fixture and transition
-- is in this transaction and the script ends in ROLLBACK.

begin;

set local timezone = 'UTC';

create temporary table migration_029_test_clock
on commit drop
as
with local_clock as (
  select (now() at time zone 'America/Denver')::date as local_today
)
select
  local_today,
  (
    local_today
    + 2
    + (
      8 - extract(isodow from local_today + 2)::integer
    ) % 7
  )::date as anchor_monday
from local_clock;


-- ---------------------------------------------------------------------------
-- 1. Exact compatibility and implementation guards
-- ---------------------------------------------------------------------------

do $test$
declare
  v_contract text[];
  v_expected_contract text[];
  v_definition text;
  v_mismatch text;
begin
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
    raise exception
      'Make-facing name/order/type contract changed: %',
      v_contract;
  end if;

  select lower(pg_get_functiondef(
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure
  ))
  into v_definition;

  if position('pg_advisory_xact_lock' in v_definition) = 0
     or position('for update' in v_definition) = 0
     or position('schedule_evaluated_at is null' in v_definition) = 0
     or position('schedule_change_proposals history' in v_definition) = 0
     or position('fixed_daily_reservation_count' in v_definition) = 0
     or position('fixed_weekly_reservation_count' in v_definition) = 0 then
    raise exception
      'Serialized generator lost a lock, history, or capacity safeguard';
  end if;

  select lower(pg_get_viewdef(
    'public.schedule_slot_reservations'::regclass,
    true
  ))
  into v_definition;

  if position('last_synced_at is null' in v_definition) = 0
     or position('last_synced_at <' in v_definition) = 0 then
    raise exception
      'Applied-target reservation no longer covers NULL or stale synchronization';
  end if;

  select string_agg(
    format('%s owner=%s security_definer=%s',
           function_record.oid::regprocedure,
           pg_get_userbyid(function_record.proowner),
           function_record.prosecdef),
    '; ' order by function_record.oid::regprocedure::text
  )
  into v_mismatch
  from pg_proc function_record
  join pg_namespace namespace
    on namespace.oid = function_record.pronamespace
  where namespace.nspname = 'public'
    and function_record.oid::regprocedure::text in (
      'find_schedule_slot_conflicts(text,text,timestamp with time zone,integer,uuid)',
      'get_schedule_reservation_capacity(text,text,timestamp with time zone,text,uuid)',
      'create_collision_safe_schedule_proposals(integer,date,date)',
      'create_content_aware_schedule_proposals(integer)',
      'refresh_schedule_proposals(date,integer)'
    )
    and (
      pg_get_userbyid(function_record.proowner) <> current_user
      or not function_record.prosecdef
      or position(
        $needle$set search_path to ''$needle$
        in lower(pg_get_functiondef(function_record.oid))
      ) = 0
    );

  if v_mismatch is not null then
    raise exception
      'Migration 029 function ownership/security/search_path changed: %',
      v_mismatch;
  end if;

  select string_agg(
    format('%s owner=%s type=%s', relation.relname,
           pg_get_userbyid(relation.relowner), relation.relkind),
    '; ' order by relation.relname
  )
  into v_mismatch
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
    and (
      pg_get_userbyid(relation.relowner) <> current_user
      or relation.relkind <> 'v'
    );

  if v_mismatch is not null then
    raise exception
      'Migration 029 relation ownership/type changed: %',
      v_mismatch;
  end if;

  if not has_function_privilege(
    'creator_dashboard_reader',
    'public.find_schedule_slot_conflicts(text,text,timestamptz,integer,uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'creator_dashboard_reader',
    'public.get_schedule_reservation_capacity(text,text,timestamptz,text,uuid)',
    'EXECUTE'
  ) then
    raise exception
      'Reporting role is missing required migration 029 helper EXECUTE';
  end if;

  if exists (
    select 1
    from (values
      ('anon'::text),
      ('authenticated'::text)
    ) denied(role_name)
    cross join (values
      ('public.find_schedule_slot_conflicts(text,text,timestamptz,integer,uuid)'::text),
      ('public.get_schedule_reservation_capacity(text,text,timestamptz,text,uuid)'::text)
    ) helper(function_signature)
    where has_function_privilege(
      denied.role_name,
      helper.function_signature,
      'EXECUTE'
    )
  ) then
    raise exception
      'anon or authenticated unexpectedly has migration 029 helper EXECUTE';
  end if;

  if exists (
    select 1
    from pg_proc function_record
    join pg_namespace namespace
      on namespace.oid = function_record.pronamespace
    cross join lateral aclexplode(
      coalesce(
        function_record.proacl,
        acldefault('f', function_record.proowner)
      )
    ) acl
    where namespace.nspname = 'public'
      and function_record.oid::regprocedure::text in (
        'find_schedule_slot_conflicts(text,text,timestamp with time zone,integer,uuid)',
        'get_schedule_reservation_capacity(text,text,timestamp with time zone,text,uuid)'
      )
      and acl.grantee = 0::oid
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception
      'PUBLIC unexpectedly has migration 029 helper EXECUTE';
  end if;

  if exists (
    select 1
    from (values
      ('anon'::text),
      ('authenticated'::text),
      ('creator_dashboard_reader'::text)
    ) denied(role_name)
    cross join (values
      ('public.schedule_slot_reservations'::text),
      ('public.schedule_change_application_preflight'::text)
    ) service_relation(relation_name)
    where has_table_privilege(
      denied.role_name,
      service_relation.relation_name,
      'SELECT'
    )
  ) then
    raise exception
      'Non-service role unexpectedly reads migration 029 service relation';
  end if;

  if exists (
    select 1
    from pg_class relation
    join pg_namespace namespace
      on namespace.oid = relation.relnamespace
    cross join lateral aclexplode(
      coalesce(relation.relacl, acldefault('r', relation.relowner))
    ) acl
    where namespace.nspname = 'public'
      and relation.relname in (
        'schedule_slot_reservations',
        'schedule_change_application_preflight'
      )
      and acl.grantee = 0::oid
      and acl.privilege_type = 'SELECT'
  ) then
    raise exception
      'PUBLIC unexpectedly reads migration 029 service relation';
  end if;

  select string_agg(
    format(
      '%s grantee=%s privilege=%s',
      relation.relname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, acl.grantee::text)
      end,
      acl.privilege_type
    ),
    '; ' order by relation.relname, acl.grantee, acl.privilege_type
  )
  into v_mismatch
  from pg_class relation
  join pg_namespace namespace
    on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(
    coalesce(relation.relacl, acldefault('r', relation.relowner))
  ) acl
  left join pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'public'
    and relation.relname in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and (
      acl.grantee = 0::oid
      or grantee.rolname in ('anon', 'authenticated')
    );

  if v_mismatch is not null then
    raise exception
      'Public web roles retain direct proposal-preview privileges: %',
      v_mismatch;
  end if;

  if not exists (
    select 1
    from pg_roles
    where rolname = 'service_role'
  ) then
    raise exception 'Required service_role is missing';
  end if;

  select array_agg(
    format(
      '%s:%s:%s',
      relation.relname,
      coalesce(grantee.rolname, 'PUBLIC'),
      acl.privilege_type
    )
    order by relation.relname, grantee.rolname, acl.privilege_type
  )
  into v_contract
  from pg_class relation
  join pg_namespace namespace
    on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(
    coalesce(relation.relacl, acldefault('r', relation.relowner))
  ) acl
  left join pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'public'
    and relation.relname in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and acl.grantee <> relation.relowner;

  select array_agg(
    format('%s:%s:SELECT', expected_view.view_name, expected_role.rolname)
    order by expected_view.view_name, expected_role.rolname
  )
  into v_expected_contract
  from (values
    ('looker_content_aware_proposal_preview'::text),
    ('looker_content_aware_proposal_preview_summary'::text)
  ) expected_view(view_name)
  cross join pg_roles expected_role
  where expected_role.rolname = 'service_role'
     or expected_role.rolname = 'creator_dashboard_reader';

  if v_contract is distinct from v_expected_contract then
    raise exception
      'Proposal-preview direct ACL contract changed: actual %, expected %',
      v_contract,
      v_expected_contract;
  end if;

  select string_agg(
    format(
      '%s updatable=%s insertable=%s',
      view_record.table_name,
      view_record.is_updatable,
      view_record.is_insertable_into
    ),
    '; ' order by view_record.table_name
  )
  into v_mismatch
  from information_schema.views view_record
  where view_record.table_schema = 'public'
    and view_record.table_name in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and (
      view_record.is_updatable <> 'NO'
      or view_record.is_insertable_into <> 'NO'
    );

  if v_mismatch is not null then
    raise exception
      'Proposal-preview view unexpectedly supports direct writes: %',
      v_mismatch;
  end if;

  select string_agg(
    format('%s trigger=%s', relation.relname, trigger_record.tgname),
    '; ' order by relation.relname, trigger_record.tgname
  )
  into v_mismatch
  from pg_class relation
  join pg_namespace namespace
    on namespace.oid = relation.relnamespace
  join pg_trigger trigger_record
    on trigger_record.tgrelid = relation.oid
  where namespace.nspname = 'public'
    and relation.relname in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and not trigger_record.tgisinternal;

  if v_mismatch is not null then
    raise exception
      'Proposal-preview view has an unexpected user-defined trigger: %',
      v_mismatch;
  end if;

end;
$test$;

create temporary table migration_029_reader_reporting_views
on commit drop
as
select
  namespace.nspname as schema_name,
  relation.relname as view_name
from pg_class relation
join pg_namespace namespace
  on namespace.oid = relation.relnamespace
cross join lateral aclexplode(
  coalesce(relation.relacl, acldefault('r', relation.relowner))
) acl
join pg_roles grantee
  on grantee.oid = acl.grantee
where namespace.nspname = 'public'
  and relation.relkind = 'v'
  and grantee.rolname = 'creator_dashboard_reader'
  and acl.privilege_type = 'SELECT';

grant select on migration_029_reader_reporting_views
to creator_dashboard_reader;

set local role creator_dashboard_reader;

do $test$
declare
  reporting_view record;
begin
  for reporting_view in
    select schema_name, view_name
    from migration_029_reader_reporting_views
    order by schema_name, view_name
  loop
    execute format(
      'select 1 from %I.%I limit 0',
      reporting_view.schema_name,
      reporting_view.view_name
    );
  end loop;
end;
$test$;

reset role;


-- ---------------------------------------------------------------------------
-- 2. Fresh recommendation, metric, label, channel, and organization fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (
  buffer_organization_id,
  name
)
values (
  '__029_REGRESSION_ORG__',
  'Migration 029 isolated regression fixture'
);

insert into public.channels (
  buffer_channel_id,
  buffer_organization_id,
  service,
  name,
  display_name,
  timezone,
  last_synced_at
)
values
  ('__029_HIST_TIKTOK__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-history-tiktok', '029 history TikTok', 'America/Denver', now()),
  ('__029_HIST_YOUTUBE__', '__029_REGRESSION_ORG__', 'youtube',
   '029-history-youtube', '029 history YouTube', 'America/Denver', now()),
  ('__029_INCIDENT_TIKTOK__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-incident', '029 historical incident', 'America/Denver', now()),
  ('__029_TIKTOK_PRIMARY__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-primary', '029 primary', 'America/Denver', now()),
  ('__029_TIKTOK_OTHER__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-other', '029 other channel', 'America/Denver', now()),
  ('__029_EIGHT_TIKTOK__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-eight-tiktok', '029 eight TikTok', 'America/Denver', now()),
  ('__029_EIGHT_YOUTUBE__', '__029_REGRESSION_ORG__', 'youtube',
   '029-eight-youtube', '029 eight YouTube', 'America/Denver', now()),
  ('__029_WEEK_CAPACITY__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-week-capacity', '029 weekly capacity', 'America/Denver', now()),
  ('__029_DAY_CAPACITY__', '__029_REGRESSION_ORG__', 'tiktok',
   '029-day-capacity', '029 daily capacity', 'America/Denver', now());

insert into public.content_items (
  id,
  internal_title,
  game,
  content_type,
  vibe,
  hook_type
)
values
  (
    '02900000-0000-0000-1000-000000000001',
    'Migration 029 TikTok recommendation group',
    '029 Game',
    '029 Short',
    '029 Vibe',
    '029 Hook'
  ),
  (
    '02900000-0000-0000-1000-000000000002',
    'Migration 029 YouTube recommendation group',
    '029 Game',
    '029 Short',
    '029 Vibe',
    '029 Hook'
  );

with recommendation_slots as (
  select
    slot.slot_number,
    (
      test_clock.anchor_monday
      + slot.day_offset
      - 28
      + time '12:15:00'
    )::timestamp as latest_local_sent_at
  from migration_029_test_clock test_clock
  cross join (values
    (1, 0),
    (2, 2),
    (3, 4),
    (4, -1)
  ) slot(slot_number, day_offset)
),
platforms as (
  select *
  from (values
    ('tiktok'::text, '__029_HIST_TIKTOK__'::text,
     '02900000-0000-0000-1000-000000000001'::uuid),
    ('youtube'::text, '__029_HIST_YOUTUBE__'::text,
     '02900000-0000-0000-1000-000000000002'::uuid)
  ) p(platform, buffer_channel_id, content_item_id)
)
insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  buffer_created_at,
  sent_at,
  last_synced_at,
  schedule_evaluated_at
)
select
  '__029_HIST_' || upper(p.platform) || '_'
    || lpad(slot.slot_number::text, 2, '0') || '_'
    || lpad(repetition.n::text, 2, '0') || '__',
  '__029_REGRESSION_ORG__',
  p.buffer_channel_id,
  p.content_item_id,
  p.platform,
  'Migration 029 recommendation history',
  'sent',
  (
    slot.latest_local_sent_at - make_interval(days => repetition.n * 7)
  ) at time zone 'America/Denver',
  (
    slot.latest_local_sent_at - make_interval(days => repetition.n * 7)
  ) at time zone 'America/Denver',
  now(),
  now()
from platforms p
cross join recommendation_slots slot
cross join generate_series(0, 2) repetition(n);

insert into public.post_metric_snapshots (
  buffer_post_id,
  captured_on,
  captured_at,
  views,
  reactions,
  comments,
  shares,
  saves,
  engagement_rate
)
select
  p.buffer_post_id,
  current_date,
  now(),
  1000,
  100,
  10,
  5,
  2,
  0.117
from public.posts p
where left(p.buffer_post_id, 11) = '__029_HIST_';

do $test$
declare
  v_count integer;
begin
  select count(*)::integer
  into v_count
  from public.looker_content_aware_recommendation_summary
  where platform in ('tiktok', 'youtube')
    and game = '029 Game'
    and content_type = '029 Short'
    and vibe = '029 Vibe'
    and model_eligible
    and recommendation_ready_for_preview;

  if v_count < 2 then
    raise exception
      'Fresh content-aware recommendation fixtures were not eligible: %',
      v_count;
  end if;

  if not exists (
    select 1
    from public.looker_weekly_slot_plan
    where platform = 'tiktok'
      and publish_iso_day = 1
      and scheduled_hour_local = 14
  ) then
    raise exception
      'Expected Monday 2 PM TikTok weekly slot was not generated';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 3. Exact historical conflict plus date-independent scheduler reproduction
-- ---------------------------------------------------------------------------

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  due_at,
  last_synced_at,
  schedule_evaluated_at
)
values
  (
    '__029_OLD_POST__',
    '__029_REGRESSION_ORG__',
    '__029_INCIDENT_TIKTOK__',
    null,
    'tiktok',
    'the covenant wasn''t even our biggest problem',
    'scheduled',
    '2026-08-24 20:00:00+00',
    '2026-08-22 09:00:18.204279+00',
    '2026-08-22 09:00:18.204279+00'
  ),
  (
    '__029_HISTORICAL_NEW_POST__',
    '__029_REGRESSION_ORG__',
    '__029_INCIDENT_TIKTOK__',
    null,
    'tiktok',
    'bro got dive bombed by a brute',
    'scheduled',
    '2026-08-25 01:30:00+00',
    '2026-08-22 09:00:18.204279+00',
    '2026-08-22 09:10:08.016344+00'
  );

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  due_at,
  last_synced_at,
  schedule_evaluated_at
)
select
  fixture.buffer_post_id,
  '__029_REGRESSION_ORG__',
  fixture.buffer_channel_id,
  '02900000-0000-0000-1000-000000000001'::uuid,
  'tiktok',
  fixture.post_text,
  'scheduled',
  (
    test_clock.anchor_monday
    + fixture.current_day_offset
    + fixture.current_local_time
  ) at time zone 'America/Denver',
  now(),
  case when fixture.is_evaluated then now() else null end
from migration_029_test_clock test_clock
cross join (values
  (
    '__029_NEW_POST__'::text,
    '__029_TIKTOK_PRIMARY__'::text,
    'bro got dive bombed by a brute'::text,
    35,
    time '19:30:00',
    false
  ),
  (
    '__029_OTHER_CHANNEL_CANDIDATE__'::text,
    '__029_TIKTOK_OTHER__'::text,
    'same target on a different Buffer channel'::text,
    36,
    time '19:30:00',
    false
  ),
  (
    '__029_EVALUATION_STAMP_BLOCK__'::text,
    '__029_TIKTOK_OTHER__'::text,
    'existing evaluation stamp must block reconsideration'::text,
    37,
    time '19:30:00',
    true
  )
) fixture(
  buffer_post_id,
  buffer_channel_id,
  post_text,
  current_day_offset,
  current_local_time,
  is_evaluated
);

-- Only the primary channel owns the dynamic anchor reservation. The other
-- channel must remain free to use the identical instant.
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
  '__029_DYNAMIC_OCCUPIED_POST__',
  '__029_REGRESSION_ORG__',
  '__029_TIKTOK_PRIMARY__',
  'tiktok',
  'Migration 029 dynamic same-channel reservation',
  'scheduled',
  (
    test_clock.anchor_monday + time '14:00:00'
  ) at time zone 'America/Denver',
  now(),
  now()
from migration_029_test_clock test_clock;

do $test$
declare
  v_min_gap_hours integer;
begin
  select min_gap_hours
  into v_min_gap_hours
  from public.scheduling_cadence_settings
  where platform = 'tiktok'
    and content_format = 'short_form';

  if v_min_gap_hours is distinct from 6 then
    raise exception
      'Historical fixture requires the configured TikTok gap to remain six hours: %',
      v_min_gap_hours;
  end if;

  if not exists (
    select 1
    from public.schedule_slot_reservations
    where reservation_kind = 'Synchronized post schedule'
      and reservation_post_id = '__029_OLD_POST__'
      and reserved_at_utc = '2026-08-24 20:00:00+00'
  ) then
    raise exception 'OLD_POST exact synchronized time is not reserved';
  end if;

  if not exists (
    select 1
    from public.find_schedule_slot_conflicts(
      '__029_HISTORICAL_NEW_POST__',
      '__029_INCIDENT_TIKTOK__',
      '2026-08-24 20:00:00+00',
      v_min_gap_hours,
      null
    ) conflict
    where conflict.reservation_post_id = '__029_OLD_POST__'
  ) then
    raise exception 'Exact OLD_POST collision was not detected';
  end if;

  if exists (
    select 1
    from public.find_schedule_slot_conflicts(
      '__029_HISTORICAL_NEW_POST__',
      '__029_TIKTOK_OTHER__',
      '2026-08-24 20:00:00+00',
      v_min_gap_hours,
      null
    ) conflict
  ) then
    raise exception
      'Historical instant was incorrectly blocked on another Buffer channel';
  end if;

  if exists (
    select 1
    from public.find_schedule_slot_conflicts(
      '__029_HISTORICAL_NEW_POST__',
      '__029_INCIDENT_TIKTOK__',
      '2026-08-25 02:00:00+00',
      v_min_gap_hours,
      null
    ) conflict
  ) then
    raise exception
      'Exact configured six-hour boundary was incorrectly blocked';
  end if;
end;
$test$;

do $test$
declare
  v_primary_target timestamptz;
  v_other_target timestamptz;
  v_anchor_target timestamptz;
  v_excluded integer;
  v_protected_hours integer;
begin
  select
    (anchor_monday + time '14:00:00')
      at time zone 'America/Denver'
  into v_anchor_target
  from migration_029_test_clock;

  select protected_hours
  into v_protected_hours
  from public.scheduling_cadence_settings
  where platform = 'tiktok'
    and content_format = 'short_form';

  if v_protected_hours is null
     or v_anchor_target <=
          now() + make_interval(hours => v_protected_hours) then
    raise exception
      'Dynamic anchor is not beyond the configured protected window: target %, hours %',
      v_anchor_target,
      v_protected_hours;
  end if;

  if not exists (
    select 1
    from public.schedule_slot_reservations
    where reservation_kind = 'Synchronized post schedule'
      and reservation_post_id = '__029_DYNAMIC_OCCUPIED_POST__'
      and reserved_at_utc = v_anchor_target
  ) then
    raise exception 'Dynamic anchor schedule is not reserved';
  end if;

  select hybrid_proposed_at_utc, excluded_collision_slot_count
  into v_primary_target, v_excluded
  from public.looker_content_aware_hybrid_shadow_schedule
  where buffer_post_id = '__029_NEW_POST__';

  if v_primary_target is null
     or v_primary_target = v_anchor_target
     or v_excluded < 1 then
    raise exception
      'Scheduler did not exclude the dynamic same-channel slot: target %, anchor %, excluded %',
      v_primary_target,
      v_anchor_target,
      v_excluded;
  end if;

  select hybrid_proposed_at_utc
  into v_other_target
  from public.looker_content_aware_hybrid_shadow_schedule
  where buffer_post_id = '__029_OTHER_CHANNEL_CANDIDATE__';

  if v_other_target is distinct from v_anchor_target then
    raise exception
      'Dynamic instant on another Buffer channel was not allowed: %, expected %',
      v_other_target,
      v_anchor_target;
  end if;

  if exists (
    select 1
    from public.looker_content_aware_proposal_preview
    where buffer_post_id = '__029_NEW_POST__'
      and proposed_due_at_utc = v_anchor_target
      and ready_to_create
  ) then
    raise exception
      'Preview marked the dynamic colliding target ready';
  end if;

  if not exists (
    select 1
    from public.looker_content_aware_proposal_preview
    where buffer_post_id = '__029_NEW_POST__'
      and proposed_due_at_utc <> v_anchor_target
      and ready_to_create
  ) then
    raise exception
      'NEW_POST did not receive a collision-safe alternative preview';
  end if;

  if not exists (
    select 1
    from public.looker_content_aware_proposal_preview
    where buffer_post_id = '__029_OTHER_CHANNEL_CANDIDATE__'
      and proposed_due_at_utc = v_anchor_target
      and ready_to_create
  ) then
    raise exception
      'Other-channel anchor target was not ready in the real preview';
  end if;

  if exists (
    select 1
    from public.looker_content_aware_hybrid_shadow_schedule
    where buffer_post_id = '__029_EVALUATION_STAMP_BLOCK__'
  ) then
    raise exception
      'Existing schedule_evaluated_at stamp did not block reconsideration';
  end if;
end;
$test$;

do $test$
declare
  v_created integer;
  v_anchor_target timestamptz;
begin
  select
    (anchor_monday + time '14:00:00')
      at time zone 'America/Denver'
  into v_anchor_target
  from migration_029_test_clock;

  v_created := public.create_content_aware_schedule_proposals(10);

  if v_created <> 2 then
    raise exception
      'Expected two dynamic-fixture safe proposals from real generator, found %',
      v_created;
  end if;

  if exists (
    select 1
    from public.schedule_change_proposals
    where buffer_post_id = '__029_NEW_POST__'
      and proposed_due_at_utc = v_anchor_target
  ) then
    raise exception
      'Real generator created the dynamic conflicting NEW_POST proposal';
  end if;

  if not exists (
    select 1
    from public.schedule_change_proposals
    where buffer_post_id = '__029_OTHER_CHANNEL_CANDIDATE__'
      and proposed_due_at_utc = v_anchor_target
      and approval_status = 'Pending'
  ) then
    raise exception
      'Real generator did not preserve same-instant different-channel safety';
  end if;

  if exists (
    select 1
    from public.schedule_change_proposals
    where buffer_post_id = '__029_EVALUATION_STAMP_BLOCK__'
  ) then
    raise exception
      'Generator reconsidered a stamped post';
  end if;
end;
$test$;

create temporary table migration_029_history_snapshot
on commit drop
as
select
  id,
  buffer_post_id,
  approval_status,
  current_due_at_utc,
  proposed_due_at_utc,
  generated_at,
  updated_at
from public.schedule_change_proposals
where buffer_post_id in (
  '__029_NEW_POST__',
  '__029_OTHER_CHANNEL_CANDIDATE__'
);

-- Clear only the evaluation stamp. Proposal history must remain sufficient.
update public.posts
set schedule_evaluated_at = null
where buffer_post_id = '__029_NEW_POST__';

do $test$
declare
  v_first integer;
  v_second integer;
  v_anchor_target timestamptz;
begin
  select
    (anchor_monday + time '14:00:00')
      at time zone 'America/Denver'
  into v_anchor_target
  from migration_029_test_clock;

  select public.refresh_schedule_proposals(local_today, 23)
  into v_first
  from migration_029_test_clock;

  select public.refresh_schedule_proposals(local_today, 23)
  into v_second
  from migration_029_test_clock;

  if v_first <> 0 or v_second <> 0 then
    raise exception
      'Proposal history did not block repeated refreshes: %, %',
      v_first,
      v_second;
  end if;

  if exists (
    select 1
    from public.schedule_change_proposals
    where buffer_post_id = '__029_NEW_POST__'
      and proposed_due_at_utc = v_anchor_target
  ) then
    raise exception
      'Refresh entry point created the dynamic conflicting NEW_POST proposal';
  end if;

  if exists (
    select 1
    from migration_029_history_snapshot before
    full join (
      select *
      from public.schedule_change_proposals
      where buffer_post_id in (
        '__029_NEW_POST__',
        '__029_OTHER_CHANNEL_CANDIDATE__'
      )
    ) after
      on after.id = before.id
    where before.id is null
       or after.id is null
       or before.buffer_post_id is distinct from after.buffer_post_id
       or before.approval_status is distinct from after.approval_status
       or before.current_due_at_utc is distinct from after.current_due_at_utc
       or before.proposed_due_at_utc is distinct from after.proposed_due_at_utc
       or before.generated_at is distinct from after.generated_at
       or before.updated_at is distinct from after.updated_at
  ) then
    raise exception
      'Repeated refresh deleted or overwrote existing proposal history';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 4. Fixed daily and weekly capacity in scheduler and application preflight
-- ---------------------------------------------------------------------------

with fixed_times as (
  select
    day_offset,
    local_hour
  from generate_series(0, 6) day_offset
  cross join (values (2), (20)) hours(local_hour)
)
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
  '__029_WEEK_FIXED_' || day_offset || '_'
    || lpad(local_hour::text, 2, '0') || '__',
  '__029_REGRESSION_ORG__',
  '__029_WEEK_CAPACITY__',
  'tiktok',
  'Migration 029 fixed weekly reservation',
  'scheduled',
  (
    test_clock.anchor_monday
    + day_offset
    + make_time(local_hour, 0, 0)
  ) at time zone 'America/Denver',
  now(),
  now()
from fixed_times
cross join migration_029_test_clock test_clock;

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
  '__029_DAY_FIXED_' || lpad(local_hour::text, 2, '0') || '__',
  '__029_REGRESSION_ORG__',
  '__029_DAY_CAPACITY__',
  'tiktok',
  'Migration 029 fixed daily reservation',
  'scheduled',
  (
    test_clock.anchor_monday + make_time(local_hour, 0, 0)
  ) at time zone 'America/Denver',
  now(),
  now()
from (values (2), (8), (20)) hours(local_hour)
cross join migration_029_test_clock test_clock;

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  due_at,
  last_synced_at,
  schedule_evaluated_at
)
select
  fixture.buffer_post_id,
  '__029_REGRESSION_ORG__',
  fixture.buffer_channel_id,
  '02900000-0000-0000-1000-000000000001'::uuid,
  'tiktok',
  fixture.post_text,
  'scheduled',
  (
    test_clock.anchor_monday
    + fixture.current_day_offset
    + fixture.current_local_time
  ) at time zone 'America/Denver',
  now(),
  null
from migration_029_test_clock test_clock
cross join (values
  (
    '__029_WEEK_CAPACITY_CANDIDATE__'::text,
    '__029_WEEK_CAPACITY__'::text,
    'Migration 029 weekly capacity candidate'::text,
    35,
    time '00:00:00'
  ),
  (
    '__029_DAY_CAPACITY_CANDIDATE__'::text,
    '__029_DAY_CAPACITY__'::text,
    'Migration 029 daily capacity candidate'::text,
    36,
    time '01:00:00'
  )
) fixture(
  buffer_post_id,
  buffer_channel_id,
  post_text,
  current_day_offset,
  current_local_time
);

do $test$
declare
  v_target timestamptz;
  v_excluded integer;
  v_anchor_monday date;
begin
  select anchor_monday
  into v_anchor_monday
  from migration_029_test_clock;

  select
    hybrid_proposed_at_utc,
    excluded_weekly_capacity_slot_count
  into v_target, v_excluded
  from public.looker_content_aware_hybrid_shadow_schedule
  where buffer_post_id = '__029_WEEK_CAPACITY_CANDIDATE__';

  if (
       v_target is not null
       and date_trunc(
          'week',
          v_target at time zone 'America/Denver'
        ) = v_anchor_monday::timestamp
     )
     or v_excluded < 1 then
    raise exception
      'Fixed weekly reservations did not consume scheduler capacity: target %, excluded %',
      v_target,
      v_excluded;
  end if;

  select
    hybrid_proposed_at_utc,
    excluded_daily_capacity_slot_count
  into v_target, v_excluded
  from public.looker_content_aware_hybrid_shadow_schedule
  where buffer_post_id = '__029_DAY_CAPACITY_CANDIDATE__';

  if (
       v_target is not null
       and (
         v_target at time zone 'America/Denver'
       )::date = v_anchor_monday
     )
     or v_excluded < 1 then
    raise exception
      'Fixed daily reservations did not consume scheduler capacity: target %, excluded %',
      v_target,
      v_excluded;
  end if;
end;
$test$;

-- Freeze these scheduler-only candidates, then create deliberately
-- capacity-blocked Approved proposals to exercise application revalidation.
update public.posts
set schedule_evaluated_at = now()
where buffer_post_id in (
  '__029_WEEK_CAPACITY_CANDIDATE__',
  '__029_DAY_CAPACITY_CANDIDATE__'
);

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
  timezone_name,
  approval_status,
  approved_at,
  generated_at,
  updated_at
)
select
  fixture.proposal_id,
  fixture.buffer_post_id,
  'tiktok',
  'short_form',
  fixture.post_text,
  post_record.due_at,
  post_record.due_at at time zone 'America/Denver',
  (
    test_clock.anchor_monday + time '14:00:00'
  ) at time zone 'America/Denver',
  test_clock.anchor_monday + time '14:00:00',
  'America/Denver',
  'Approved',
  now(),
  now(),
  now()
from migration_029_test_clock test_clock
cross join (values
  (
    '02900000-0000-0000-2000-000000000001'::uuid,
    '__029_WEEK_CAPACITY_CANDIDATE__'::text,
    'Migration 029 weekly capacity candidate'::text
  ),
  (
    '02900000-0000-0000-2000-000000000002'::uuid,
    '__029_DAY_CAPACITY_CANDIDATE__'::text,
    'Migration 029 daily capacity candidate'::text
  )
) fixture(proposal_id, buffer_post_id, post_text)
join public.posts post_record
  on post_record.buffer_post_id = fixture.buffer_post_id;

do $test$
declare
  v_reasons text[];
begin
  select blocking_reasons
  into v_reasons
  from public.schedule_change_application_preflight
  where proposal_id = '02900000-0000-0000-2000-000000000001';

  if not (
    'Blocked: fixed reservations plus this target exceed weekly channel capacity'
      = any(v_reasons)
  ) then
    raise exception
      'Application preflight did not block full weekly capacity: %',
      v_reasons;
  end if;

  select blocking_reasons
  into v_reasons
  from public.schedule_change_application_preflight
  where proposal_id = '02900000-0000-0000-2000-000000000002';

  if not (
    'Blocked: fixed reservations plus this target exceed daily channel capacity'
      = any(v_reasons)
  ) then
    raise exception
      'Application preflight did not block full daily capacity: %',
      v_reasons;
  end if;

  if exists (
    select 1
    from public.approved_schedule_changes_ready_to_apply
    where proposal_id in (
      '02900000-0000-0000-2000-000000000001',
      '02900000-0000-0000-2000-000000000002'
    )
  ) then
    raise exception
      'Make-facing view exposed a daily/weekly capacity violation';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 5. Real eight-post preview, generator, approval, and application workflow
-- ---------------------------------------------------------------------------

-- One fixed post in every preview-calendar week proves fixed reservations are
-- included in the successful targets' weekly totals without exhausting them.
with fixed_weeks as (
  select distinct
    (
      date_trunc('week', calendar_day.local_timestamp)
      + interval '5 days'
    )::date as local_date
  from migration_029_test_clock test_clock
  cross join lateral generate_series(
    (test_clock.local_today + 2)::timestamp,
    (test_clock.local_today + 23)::timestamp,
    interval '1 day'
  ) calendar_day(local_timestamp)
),
channels as (
  select *
  from (values
    ('__029_EIGHT_TIKTOK__'::text, 'tiktok'::text),
    ('__029_EIGHT_YOUTUBE__'::text, 'youtube'::text)
  ) channels(buffer_channel_id, platform)
)
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
  '__029_EIGHT_FIXED_' || upper(channel.platform) || '_'
    || to_char(week.local_date, 'YYYYMMDD') || '__',
  '__029_REGRESSION_ORG__',
  channel.buffer_channel_id,
  channel.platform,
  'Migration 029 eight-post fixed weekly reservation',
  'scheduled',
  (
    week.local_date + time '03:00:00'
  ) at time zone 'America/Denver',
  now() - interval '1 hour',
  now()
from fixed_weeks week
cross join channels channel;

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  due_at,
  last_synced_at,
  schedule_evaluated_at
)
select
  '__029_EIGHT_' || lpad(gs.n::text, 2, '0') || '__',
  '__029_REGRESSION_ORG__',
  case
    when gs.n <= 4 then '__029_EIGHT_TIKTOK__'
    else '__029_EIGHT_YOUTUBE__'
  end,
  case
    when gs.n <= 4
      then '02900000-0000-0000-1000-000000000001'::uuid
    else '02900000-0000-0000-1000-000000000002'::uuid
  end,
  case when gs.n <= 4 then 'tiktok' else 'youtube' end,
  'Migration 029 real generator candidate ' || gs.n,
  'scheduled',
  (
    test_clock.anchor_monday
    + 35
    + ((gs.n - 1) % 4)
    + time '19:30:00'
  ) at time zone 'America/Denver',
  now() - interval '1 hour',
  null
from generate_series(1, 8) gs(n)
cross join migration_029_test_clock test_clock;

do $test$
declare
  v_count integer;
begin
  select count(*)::integer
  into v_count
  from public.looker_content_aware_proposal_preview
  where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    and ready_to_create
    and preview_status = 'Ready'
    and recommendation_ready_for_preview
    and shadow_ready_for_live_test
    and hybrid_guardrail_status = 'Pass'
    and current_fixed_weekly_reservation_count >= 1
    and projected_weekly_post_count <= configured_posts_per_week
    and projected_daily_post_count <= max_posts_per_day;

  if v_count <> 8 then
    raise exception
      'Expected exactly eight genuinely ready real preview rows, found %',
      v_count;
  end if;

  if exists (
    select 1
    from public.posts candidate
    where candidate.buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
      and (
        candidate.schedule_evaluated_at is not null
        or exists (
          select 1
          from public.schedule_change_proposals history
          where history.buffer_post_id = candidate.buffer_post_id
        )
      )
  ) then
    raise exception
      'Eight-post candidates were not genuinely unevaluated/history-free';
  end if;
end;
$test$;

do $test$
declare
  v_created integer;
  v_count integer;
begin
  v_created := public.create_content_aware_schedule_proposals(50);

  if v_created <> 8 then
    raise exception
      'Real proposal-generation path created %, expected exactly eight',
      v_created;
  end if;

  select count(*)::integer
  into v_count
  from public.schedule_change_proposals
  where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    and approval_status = 'Pending';

  if v_count <> 8 then
    raise exception
      'Expected eight Pending proposals from real generator, found %',
      v_count;
  end if;
end;
$test$;

-- Verify the full proposed batch and every one of its 256 possible approval
-- subsets against synchronized/fixed schedules, channel gaps, day limits, and
-- local Monday-based week capacity.
do $test$
declare
  v_violation text;
begin
  with eight_proposals as (
    select
      proposal.id as proposal_id,
      proposal.buffer_post_id,
      post_record.buffer_channel_id,
      proposal.proposed_due_at_utc,
      row_number() over (order by proposal.buffer_post_id) - 1
        as bit_number
    from public.schedule_change_proposals proposal
    join public.posts post_record
      on post_record.buffer_post_id = proposal.buffer_post_id
    where proposal.buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
  ),
  masks as (
    select generate_series(0, 255)::integer as mask
  ),
  scenario_reservations as (
    select distinct
      mask.mask,
      reservation.reservation_post_id,
      reservation.buffer_channel_id,
      reservation.reserved_at_utc
    from masks mask
    join public.schedule_slot_reservations reservation
      on reservation.buffer_channel_id in (
        '__029_EIGHT_TIKTOK__',
        '__029_EIGHT_YOUTUBE__'
      )
    where not exists (
      select 1
      from eight_proposals proposal_target
      where proposal_target.proposal_id =
            reservation.reservation_proposal_id
    )
      and not exists (
        select 1
        from eight_proposals selected
        where selected.buffer_post_id =
              reservation.reservation_post_id
          and (
            mask.mask & (1 << selected.bit_number::integer)
          ) <> 0
      )

    union

    select
      mask.mask,
      selected.buffer_post_id,
      selected.buffer_channel_id,
      selected.proposed_due_at_utc
    from masks mask
    join eight_proposals selected
      on (
        mask.mask & (1 << selected.bit_number::integer)
      ) <> 0
  ),
  channel_settings as (
    select
      channel_record.buffer_channel_id,
      settings.min_gap_hours,
      settings.max_posts_per_day,
      settings.posts_per_week,
      settings.protected_hours,
      settings.timezone_name
    from public.channels channel_record
    join public.scheduling_cadence_settings settings
      on settings.platform = channel_record.service
     and settings.content_format = 'short_form'
    where channel_record.buffer_channel_id in (
      '__029_EIGHT_TIKTOK__',
      '__029_EIGHT_YOUTUBE__'
    )
  ),
  collision_violation as (
    select format(
      'mask %s collision on %s between %s and %s',
      a.mask,
      a.buffer_channel_id,
      a.reservation_post_id,
      b.reservation_post_id
    ) as message
    from scenario_reservations a
    join scenario_reservations b
      on b.mask = a.mask
     and b.buffer_channel_id = a.buffer_channel_id
     and (b.reservation_post_id, b.reserved_at_utc) >
         (a.reservation_post_id, a.reserved_at_utc)
    join channel_settings settings
      on settings.buffer_channel_id = a.buffer_channel_id
    where a.reserved_at_utc >
            b.reserved_at_utc
            - make_interval(hours => settings.min_gap_hours)
      and a.reserved_at_utc <
            b.reserved_at_utc
            + make_interval(hours => settings.min_gap_hours)
    limit 1
  ),
  daily_capacity_violation as (
    select format(
      'mask %s daily capacity on %s: %s/%s on %s',
      reservations.mask,
      reservations.buffer_channel_id,
      count(*),
      settings.max_posts_per_day,
      (
        reservations.reserved_at_utc
        at time zone settings.timezone_name
      )::date
    ) as message
    from scenario_reservations reservations
    join channel_settings settings
      on settings.buffer_channel_id = reservations.buffer_channel_id
    group by
      reservations.mask,
      reservations.buffer_channel_id,
      settings.max_posts_per_day,
      settings.timezone_name,
      (
        reservations.reserved_at_utc
        at time zone settings.timezone_name
      )::date
    having count(*) > settings.max_posts_per_day
    limit 1
  ),
  weekly_capacity_violation as (
    select format(
      'mask %s weekly capacity on %s: %s/%s in week %s',
      reservations.mask,
      reservations.buffer_channel_id,
      count(*),
      settings.posts_per_week,
      date_trunc(
        'week',
        reservations.reserved_at_utc
        at time zone settings.timezone_name
      )
    ) as message
    from scenario_reservations reservations
    join channel_settings settings
      on settings.buffer_channel_id = reservations.buffer_channel_id
    group by
      reservations.mask,
      reservations.buffer_channel_id,
      settings.posts_per_week,
      settings.timezone_name,
      date_trunc(
        'week',
        reservations.reserved_at_utc
        at time zone settings.timezone_name
      )
    having count(*) > settings.posts_per_week
    limit 1
  )
  select message
  into v_violation
  from (
    select message from collision_violation
    union all
    select message from daily_capacity_violation
    union all
    select message from weekly_capacity_violation
  ) violations
  limit 1;

  if v_violation is not null then
    raise exception
      'Arbitrary approval-subset safety failed: %',
      v_violation;
  end if;

  if exists (
    select 1
    from public.schedule_change_proposals proposal
    join public.posts post_record
      on post_record.buffer_post_id = proposal.buffer_post_id
    join public.scheduling_cadence_settings settings
      on settings.platform = proposal.platform
     and settings.content_format = proposal.content_format
    where proposal.buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
      and proposal.proposed_due_at_utc <=
            now() + make_interval(hours => settings.protected_hours)
  ) then
    raise exception
      'Real generator created a target inside the protected window';
  end if;
end;
$test$;

-- Use the existing approval RPC, then require all eight to pass the new
-- application preflight and unchanged Make feed.
do $test$
declare
  v_proposal record;
  v_count integer;
begin
  for v_proposal in
    select id
    from public.schedule_change_proposals
    where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    order by id
  loop
    if not public.set_schedule_proposal_decision(
      v_proposal.id,
      'Approved'
    ) then
      raise exception 'Could not approve proposal %', v_proposal.id;
    end if;
  end loop;

  select count(*)::integer
  into v_count
  from public.schedule_change_application_preflight
  where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    and is_ready
    and reservation_conflict_count = 0
    and projected_daily_post_count <= max_posts_per_day
    and projected_weekly_post_count <= posts_per_week;

  if v_count <> 8 then
    raise exception
      'Expected all eight Approved proposals to pass application preflight, found %',
      v_count;
  end if;

  select count(*)::integer
  into v_count
  from public.approved_schedule_changes_ready_to_apply
  where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$';

  if v_count <> 8 then
    raise exception
      'Unchanged Make-facing view did not expose all eight safe proposals: %',
      v_count;
  end if;
end;
$test$;

do $test$
declare
  v_proposal record;
  v_count integer;
begin
  for v_proposal in
    select proposal_id
    from public.approved_schedule_changes_ready_to_apply
    where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    order by proposal_id
  loop
    if not public.mark_schedule_proposal_applied(
      v_proposal.proposal_id,
      'Migration 029 isolated eight-post success'
    ) then
      raise exception
        'Could not mark proposal % Applied',
        v_proposal.proposal_id;
    end if;
  end loop;

  select count(*)::integer
  into v_count
  from public.schedule_change_proposals
  where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    and approval_status = 'Applied'
    and error_message is null;

  if v_count <> 8 then
    raise exception
      'Expected eight successful Applied proposals, found %',
      v_count;
  end if;

  select count(distinct reservation_post_id)::integer
  into v_count
  from public.schedule_slot_reservations
  where reservation_kind =
        'Applied target awaiting synchronization'
    and reservation_post_id ~ '^__029_EIGHT_[0-9]{2}__$';

  if v_count <> 8 then
    raise exception
      'Expected eight temporary Applied-target reservations, found %',
      v_count;
  end if;
end;
$test$;

create temporary table migration_029_applied_history_snapshot
on commit drop
as
select
  id,
  buffer_post_id,
  approval_status,
  current_due_at_utc,
  proposed_due_at_utc,
  generated_at,
  approved_at,
  applied_at,
  result_message,
  error_message
from public.schedule_change_proposals
where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$';

-- Simulate a later synchronized Buffer read, clear evaluation stamps, and
-- prove proposal history alone prevents any second scheduling cycle.
update public.posts post_record
set
  due_at = proposal.proposed_due_at_utc,
  last_synced_at = proposal.applied_at + interval '1 second',
  schedule_evaluated_at = null
from public.schedule_change_proposals proposal
where proposal.buffer_post_id = post_record.buffer_post_id
  and post_record.buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
  and proposal.approval_status = 'Applied';

do $test$
declare
  v_first integer;
  v_second integer;
begin
  select public.refresh_schedule_proposals(local_today, 23)
  into v_first
  from migration_029_test_clock;

  select public.refresh_schedule_proposals(local_today, 23)
  into v_second
  from migration_029_test_clock;

  if v_first <> 0 or v_second <> 0 then
    raise exception
      'Repeated post-application refresh created proposals: %, %',
      v_first,
      v_second;
  end if;

  if exists (
    select 1
    from migration_029_applied_history_snapshot before
    full join (
      select *
      from public.schedule_change_proposals
      where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
    ) after
      on after.id = before.id
    where before.id is null
       or after.id is null
       or before.buffer_post_id is distinct from after.buffer_post_id
       or before.approval_status is distinct from after.approval_status
       or before.current_due_at_utc is distinct from after.current_due_at_utc
       or before.proposed_due_at_utc is distinct from after.proposed_due_at_utc
       or before.generated_at is distinct from after.generated_at
       or before.approved_at is distinct from after.approved_at
       or before.applied_at is distinct from after.applied_at
       or before.result_message is distinct from after.result_message
       or before.error_message is distinct from after.error_message
  ) then
    raise exception
      'Repeated refresh deleted or overwrote Applied proposal history';
  end if;

  if exists (
    select 1
    from public.looker_content_aware_hybrid_shadow_schedule
    where buffer_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
  ) then
    raise exception
      'History-free filter reconsidered Applied posts after stamps were cleared';
  end if;

  if exists (
    select 1
    from public.schedule_slot_reservations
    where reservation_kind =
          'Applied target awaiting synchronization'
      and reservation_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
  ) then
    raise exception
      'Temporary Applied targets survived a later synchronization';
  end if;

  if (
    select count(distinct reservation_post_id)
    from public.schedule_slot_reservations
    where reservation_kind = 'Synchronized post schedule'
      and reservation_post_id ~ '^__029_EIGHT_[0-9]{2}__$'
  ) <> 8 then
    raise exception
      'Later synchronization did not leave eight authoritative posts.due_at reservations';
  end if;
end;
$test$;


rollback;
