-- Creator Analytics
-- Regression coverage for migration 035
-- File: Tests/Database/035_add_controlled_web_labeling_regression.sql
--
-- First retain the full migration-034 regression. Then prove the dedicated
-- labeler can use only the new audited wrapper, can label only rows that have
-- not reached Sheets, and cannot silently change an existing Clip Group.

\ir 034_restrict_internal_schedule_generator_execution_regression.sql

begin;

set local timezone = 'UTC';
set local statement_timeout = '90s';
set local lock_timeout = '5s';


-- ---------------------------------------------------------------------------
-- 1. Security boundary
-- ---------------------------------------------------------------------------

do $test$
declare
  v_unexpected text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_labeler'
      and rolcanlogin
      and not rolsuper
      and not rolcreatedb
      and not rolcreaterole
      and not rolinherit
      and not rolreplication
      and not rolbypassrls
  ) then
    raise exception 'Migration 035 labeler role is not fail-closed';
  end if;

  if not pg_catalog.has_function_privilege(
       'creator_analytics_web_labeler',
       'public.process_content_label_payload_for_web(jsonb,text,text,boolean)',
       'EXECUTE'
     ) then
    raise exception 'Migration 035 wrapper is not executable by labeler';
  end if;

  if pg_catalog.has_function_privilege(
       'service_role',
       'public.process_content_label_payload_for_web(jsonb,text,text,boolean)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'creator_analytics_web_reader',
       'public.process_content_label_payload_for_web(jsonb,text,text,boolean)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'public.process_content_label_payload_for_web(jsonb,text,text,boolean)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'authenticated',
       'public.process_content_label_payload_for_web(jsonb,text,text,boolean)',
       'EXECUTE'
     ) then
    raise exception 'Migration 035 wrapper has an unexpected executor';
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
      'process_content_label_payload',
      'process_content_label_row',
      'mark_label_queue_exported',
      'sync_buffer_posts',
      'sync_buffer_metrics',
      'set_schedule_proposal_decision',
      'refresh_schedule_proposals'
    )
    and pg_catalog.has_function_privilege(
      'creator_analytics_web_labeler',
      function_record.oid,
      'EXECUTE'
    );

  if v_unexpected is not null then
    raise exception 'Labeler can execute unrelated functions: %', v_unexpected;
  end if;

  if pg_catalog.has_table_privilege(
       'creator_analytics_web_labeler',
       'public.posts',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'creator_analytics_web_labeler',
       'public.content_items',
       'SELECT,INSERT,UPDATE,DELETE'
     )
     or pg_catalog.has_table_privilege(
       'creator_analytics_web_labeler',
       'public.web_labeling_events',
       'SELECT,INSERT,UPDATE,DELETE'
     ) then
    raise exception 'Labeler has direct table privileges';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'creator_app'
      and table_name = 'looker_dashboard_posts'
      and column_name = 'vibe'
  ) then
    raise exception 'Shared-label read projection is missing vibe';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class index_relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = index_relation.relnamespace
    join pg_catalog.pg_index index_record
      on index_record.indexrelid = index_relation.oid
    where namespace.nspname = 'public'
      and index_relation.relname =
        'content_items_internal_title_normalized_unique_idx'
      and index_record.indisunique
      and index_record.indisvalid
  ) then
    raise exception 'Normalized Clip Group identity is not enforced';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Transactional fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (buffer_organization_id, name)
values ('MIGRATION_035_ORG', 'Migration 035 fixture');

insert into public.channels (
  buffer_channel_id,
  buffer_organization_id,
  service,
  name,
  timezone
)
values (
  'MIGRATION_035_CHANNEL',
  'MIGRATION_035_ORG',
  'tiktok',
  'migration_035',
  'America/Denver'
);

insert into public.content_items (
  id,
  internal_title,
  game,
  content_type,
  vibe,
  hook_type,
  duration_seconds,
  editing_intensity,
  source_recording,
  notes
)
values (
  '35000000-0000-0000-0000-000000000001',
  'Existing Shared Group',
  'Minecraft',
  'Clutch',
  'Intense',
  'Immediate action',
  42,
  'Heavy',
  'existing-source',
  'existing-note'
);

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  sent_at,
  label_queue_exported_at
)
values
  (
    'MIGRATION_035_NEW',
    'MIGRATION_035_ORG',
    'MIGRATION_035_CHANNEL',
    null,
    'tiktok',
    'New group fixture',
    'sent',
    now(),
    null
  ),
  (
    'MIGRATION_035_LINK',
    'MIGRATION_035_ORG',
    'MIGRATION_035_CHANNEL',
    null,
    'tiktok',
    'Existing group link fixture',
    'sent',
    now(),
    null
  ),
  (
    'MIGRATION_035_EXPORTED',
    'MIGRATION_035_ORG',
    'MIGRATION_035_CHANNEL',
    null,
    'tiktok',
    'Sheets-owned fixture',
    'sent',
    now(),
    now()
  ),
  (
    'MIGRATION_035_ALREADY_LINKED',
    'MIGRATION_035_ORG',
    'MIGRATION_035_CHANNEL',
    '35000000-0000-0000-0000-000000000001',
    'tiktok',
    'Existing linked fixture',
    'sent',
    now(),
    now()
  ),
  (
    'MIGRATION_035_DUPLICATE_NAME',
    'MIGRATION_035_ORG',
    'MIGRATION_035_CHANNEL',
    null,
    'tiktok',
    'Duplicate name fixture',
    'sent',
    now(),
    null
  );


-- ---------------------------------------------------------------------------
-- 3. Execute only through the labeler role
-- ---------------------------------------------------------------------------

grant creator_analytics_web_labeler
to current_user
with set true, inherit false;

set local role creator_analytics_web_labeler;

select *
from public.process_content_label_payload_for_web(
  '{
    "post_id": "MIGRATION_035_NEW",
    "clip_group": "New Web Group",
    "game": "Arc Raiders",
    "content_type": "Funny moment",
    "vibe": "Chaotic",
    "hook_type": "Immediate action",
    "duration_seconds": "45",
    "editing_intensity": "Medium",
    "source_recording": "fixture-source",
    "notes": "fixture-note"
  }'::jsonb,
  'operator@example.invalid',
  'create',
  false
);

do $test$
begin
  perform *
  from public.process_content_label_payload_for_web(
    '{
      "post_id": "MIGRATION_035_EXPORTED",
      "clip_group": "Exported Web Group",
      "game": "Arc Raiders",
      "content_type": "Funny moment",
      "vibe": "Chaotic"
    }'::jsonb,
    'operator@example.invalid',
    'create',
    false
  );
  raise exception 'Expected exported-row ownership failure';
exception
  when sqlstate 'P3002' then null;
end;
$test$;

do $test$
begin
  perform *
  from public.process_content_label_payload_for_web(
    '{
      "post_id": "MIGRATION_035_LINK",
      "clip_group": "Existing Shared Group"
    }'::jsonb,
    'operator@example.invalid',
    'link_existing',
    false
  );
  raise exception 'Expected shared-effect confirmation failure';
exception
  when sqlstate 'P3003' then null;
end;
$test$;

select *
from public.process_content_label_payload_for_web(
  '{
    "post_id": "MIGRATION_035_LINK",
    "clip_group": "Existing Shared Group",
    "game": "Other",
    "content_type": "Other",
    "vibe": "Funny"
  }'::jsonb,
  'operator@example.invalid',
  'link_existing',
  true
);

do $test$
begin
  perform *
  from public.process_content_label_payload_for_web(
    '{
      "post_id": "MIGRATION_035_DUPLICATE_NAME",
      "clip_group": "Existing Shared Group",
      "game": "Other",
      "content_type": "Other",
      "vibe": "Funny"
    }'::jsonb,
    'operator@example.invalid',
    'create',
    false
  );
  raise exception 'Expected duplicate Clip Group mode failure';
exception
  when sqlstate 'P3005' then null;
end;
$test$;

reset role;

revoke creator_analytics_web_labeler
from current_user
granted by current_user;


-- ---------------------------------------------------------------------------
-- 4. Behavioral and audit assertions
-- ---------------------------------------------------------------------------

do $test$
declare
  v_existing public.content_items%rowtype;
begin
  if not exists (
    select 1
    from public.posts post_record
    join public.content_items content_item
      on content_item.id = post_record.content_item_id
    where post_record.buffer_post_id = 'MIGRATION_035_NEW'
      and content_item.internal_title = 'new web group'
      and content_item.game = 'Arc Raiders'
      and content_item.content_type = 'Funny moment'
      and content_item.vibe = 'Chaotic'
  ) then
    raise exception 'New app-owned label was not created correctly';
  end if;

  if public.mark_label_queue_exported('MIGRATION_035_NEW') then
    raise exception 'Make export marker accepted a post already labeled by the app';
  end if;

  if exists (
    select 1
    from public.posts
    where buffer_post_id = 'MIGRATION_035_NEW'
      and label_queue_exported_at is not null
  ) then
    raise exception 'A labeled post received a misleading Sheet export timestamp';
  end if;

  if not exists (
    select 1
    from public.posts
    where buffer_post_id = 'MIGRATION_035_LINK'
      and content_item_id = '35000000-0000-0000-0000-000000000001'
  ) then
    raise exception 'Existing shared Clip Group was not linked';
  end if;

  select *
  into strict v_existing
  from public.content_items
  where id = '35000000-0000-0000-0000-000000000001';

  if v_existing.game <> 'Minecraft'
     or v_existing.internal_title <> 'Existing Shared Group'
     or v_existing.content_type <> 'Clutch'
     or v_existing.vibe <> 'Intense'
     or v_existing.notes <> 'existing-note' then
    raise exception 'Existing Clip Group labels were changed by link mode';
  end if;

  if exists (
    select 1
    from public.posts
    where buffer_post_id in (
      'MIGRATION_035_EXPORTED',
      'MIGRATION_035_DUPLICATE_NAME'
    )
      and content_item_id is not null
  ) then
    raise exception 'A rejected labeling attempt changed a post';
  end if;

  if (
    select count(*)
    from public.web_labeling_events
    where buffer_post_id like 'MIGRATION_035_%'
  ) <> 2 then
    raise exception 'Successful labeling audit count is incorrect';
  end if;

  if not exists (
    select 1
    from public.web_labeling_events
    where buffer_post_id = 'MIGRATION_035_NEW'
      and actor_email = 'operator@example.invalid'
      and operation = 'create'
      and affected_post_count = 1
  )
     or not exists (
       select 1
       from public.web_labeling_events
       where buffer_post_id = 'MIGRATION_035_LINK'
         and actor_email = 'operator@example.invalid'
         and operation = 'link_existing'
         and affected_post_count = 2
     ) then
    raise exception 'Labeling audit details are incorrect';
  end if;
end;
$test$;

-- All fixtures and audit rows are transactional.
rollback;
