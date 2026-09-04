-- Creator Analytics
-- Regression coverage for migration 036
-- File: Tests/Database/036_add_atomic_label_queue_export_claims_regression.sql
--
-- Retain the full migration-035 suite, then prove Make and the web labeler
-- cannot own the same Label Queue row. All fixtures and claims roll back.

\ir 035_add_controlled_web_labeling_regression.sql

begin;

set local timezone = 'UTC';
set local statement_timeout = '90s';
set local lock_timeout = '5s';


-- ---------------------------------------------------------------------------
-- 1. Security and shape
-- ---------------------------------------------------------------------------

do $test$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'posts'
      and column_name = 'label_queue_claim_token'
      and data_type = 'uuid'
  ) or not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'posts'
      and column_name = 'label_queue_claimed_at'
      and data_type = 'timestamp with time zone'
  ) then
    raise exception 'Migration 036 claim columns are missing';
  end if;

  if pg_catalog.has_table_privilege(
       'service_role',
       'public.pending_label_queue_exports',
       'SELECT'
     ) then
    raise exception 'Service role can still bypass the atomic claim';
  end if;

  if pg_catalog.has_function_privilege(
       'service_role',
       'public.mark_label_queue_exported(text)',
       'EXECUTE'
     ) then
    raise exception 'Service role can still use the legacy export marker';
  end if;

  if not pg_catalog.has_function_privilege(
       'service_role',
       'public.claim_pending_label_queue_exports(integer)',
       'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'service_role',
       'public.mark_label_queue_exported(text,uuid)',
       'EXECUTE'
     ) then
    raise exception 'Service role cannot execute the atomic claim protocol';
  end if;

  if pg_catalog.has_function_privilege(
       'creator_analytics_web_labeler',
       'public.claim_pending_label_queue_exports(integer)',
       'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'creator_analytics_web_labeler',
       'public.mark_label_queue_exported(text,uuid)',
       'EXECUTE'
     ) then
    raise exception 'Web labeler can execute Make claim functions';
  end if;

  if not pg_catalog.has_table_privilege(
       'creator_analytics_web_reader',
       'creator_app.pending_label_queue_exports',
       'SELECT'
     ) then
    raise exception 'Web reader cannot inspect safe claim state';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'creator_app'
      and table_name = 'pending_label_queue_exports'
      and column_name = 'claim_token'
  ) then
    raise exception 'Private web projection exposes a claim token';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Transactional fixtures
-- ---------------------------------------------------------------------------

insert into public.organizations (buffer_organization_id, name)
values ('MIGRATION_036_ORG', 'Migration 036 fixture');

insert into public.channels (
  buffer_channel_id,
  buffer_organization_id,
  service,
  name,
  timezone
)
values (
  'MIGRATION_036_CHANNEL',
  'MIGRATION_036_ORG',
  'tiktok',
  'migration_036',
  'America/Denver'
);

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  channel_service,
  post_text,
  status,
  sent_at,
  label_queue_exported_at
)
values
  (
    'MIGRATION_036_CLAIM',
    'MIGRATION_036_ORG',
    'MIGRATION_036_CHANNEL',
    'tiktok',
    'Atomic claim fixture',
    'sent',
    '1900-01-01 00:00:00+00',
    null
  ),
  (
    'MIGRATION_036_EXPORTED',
    'MIGRATION_036_ORG',
    'MIGRATION_036_CHANNEL',
    'tiktok',
    'Already exported fixture',
    'sent',
    '1900-01-02 00:00:00+00',
    now()
  );

create temporary table migration_036_claim_result
on commit drop
as
select *
from public.claim_pending_label_queue_exports(1)
with no data;

create temporary table migration_036_finalize_result (
  attempt text primary key,
  changed boolean not null
) on commit drop;

grant select, insert on migration_036_claim_result to service_role;
grant select, insert on migration_036_finalize_result to service_role;


-- ---------------------------------------------------------------------------
-- 3. Make claims exactly once through service_role
-- ---------------------------------------------------------------------------

grant service_role
to current_user
with set true, inherit false;

set local role service_role;

insert into pg_temp.migration_036_claim_result
select *
from public.claim_pending_label_queue_exports(1);

reset role;

do $test$
begin
  if (
    select count(*)
    from pg_temp.migration_036_claim_result
  ) <> 1 or not exists (
    select 1
    from pg_temp.migration_036_claim_result
    where buffer_post_id = 'MIGRATION_036_CLAIM'
      and claim_token is not null
  ) then
    raise exception 'Atomic Make claim returned the wrong row or token';
  end if;

  if not exists (
    select 1
    from public.posts post_record
    where post_record.buffer_post_id = 'MIGRATION_036_CLAIM'
      and post_record.label_queue_claim_token = (
        select claim_token
        from pg_temp.migration_036_claim_result
      )
      and post_record.label_queue_claimed_at is not null
      and post_record.label_queue_exported_at is null
  ) then
    raise exception 'Atomic Make claim was not persisted';
  end if;

  if not exists (
    select 1
    from creator_app.pending_label_queue_exports
    where buffer_post_id = 'MIGRATION_036_CLAIM'
      and queue_state = 'export_in_progress'
      and claimed_at is not null
  ) then
    raise exception 'Web projection does not show the claimed ownership state';
  end if;
end;
$test$;

create temporary table migration_036_second_claim
on commit drop
as
select *
from public.claim_pending_label_queue_exports(100)
with no data;

grant select, insert on migration_036_second_claim to service_role;

set local role service_role;

insert into pg_temp.migration_036_second_claim
select *
from public.claim_pending_label_queue_exports(100);

reset role;

do $test$
begin
  if exists (
    select 1
    from pg_temp.migration_036_second_claim
    where buffer_post_id = 'MIGRATION_036_CLAIM'
  ) then
    raise exception 'A claimed row was claimed a second time';
  end if;

  if exists (
    select 1
    from pg_temp.migration_036_second_claim
    where buffer_post_id = 'MIGRATION_036_EXPORTED'
  ) then
    raise exception 'An exported row was claimed';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 4. A Make-owned row rejects the web labeler
-- ---------------------------------------------------------------------------

grant creator_analytics_web_labeler
to current_user
with set true, inherit false;

set local role creator_analytics_web_labeler;

do $test$
begin
  perform *
  from public.process_content_label_payload_for_web(
    '{
      "post_id": "MIGRATION_036_CLAIM",
      "clip_group": "Claimed Web Group",
      "game": "Arc Raiders",
      "content_type": "Funny moment",
      "vibe": "Chaotic"
    }'::jsonb,
    'operator@example.invalid',
    'create',
    false
  );
  raise exception 'Expected claimed-row ownership failure';
exception
  when sqlstate 'P3007' then null;
end;
$test$;

reset role;

do $test$
begin
  if exists (
    select 1
    from public.posts
    where buffer_post_id = 'MIGRATION_036_CLAIM'
      and content_item_id is not null
  ) or exists (
    select 1
    from public.web_labeling_events
    where buffer_post_id = 'MIGRATION_036_CLAIM'
  ) then
    raise exception 'Rejected claimed-row labeling changed state or audit';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 5. Only the exact claim token can finalize, and finalization is idempotent
-- ---------------------------------------------------------------------------

set local role service_role;

insert into pg_temp.migration_036_finalize_result (attempt, changed)
values (
  'wrong-token',
  public.mark_label_queue_exported(
    'MIGRATION_036_CLAIM',
    '36000000-0000-0000-0000-000000000099'::uuid
  )
);

insert into pg_temp.migration_036_finalize_result (attempt, changed)
select
  'correct-token',
  public.mark_label_queue_exported(
    'MIGRATION_036_CLAIM',
    claim_token
  )
from pg_temp.migration_036_claim_result;

insert into pg_temp.migration_036_finalize_result (attempt, changed)
select
  'duplicate-finalize',
  public.mark_label_queue_exported(
    'MIGRATION_036_CLAIM',
    claim_token
  )
from pg_temp.migration_036_claim_result;

reset role;

do $test$
begin
  if (
    select changed
    from pg_temp.migration_036_finalize_result
    where attempt = 'wrong-token'
  ) then
    raise exception 'An incorrect claim token finalized an export';
  end if;

  if not (
    select changed
    from pg_temp.migration_036_finalize_result
    where attempt = 'correct-token'
  ) then
    raise exception 'The exact claim token did not finalize its export';
  end if;

  if (
    select changed
    from pg_temp.migration_036_finalize_result
    where attempt = 'duplicate-finalize'
  ) then
    raise exception 'Duplicate finalization was not idempotent';
  end if;

  if not exists (
    select 1
    from public.posts
    where buffer_post_id = 'MIGRATION_036_CLAIM'
      and label_queue_exported_at is not null
      and label_queue_claim_token is not null
  ) or not exists (
    select 1
    from creator_app.pending_label_queue_exports
    where buffer_post_id = 'MIGRATION_036_CLAIM'
      and queue_state = 'exported_unlinked'
  ) then
    raise exception 'Finalized export state is incorrect';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 6. An app-owned row cannot subsequently be claimed by Make
-- ---------------------------------------------------------------------------

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  channel_service,
  post_text,
  status,
  sent_at
)
values (
  'MIGRATION_036_APP',
  'MIGRATION_036_ORG',
  'MIGRATION_036_CHANNEL',
  'tiktok',
  'App ownership fixture',
  'sent',
  '1899-01-01 00:00:00+00'
);

set local role creator_analytics_web_labeler;

select *
from public.process_content_label_payload_for_web(
  '{
    "post_id": "MIGRATION_036_APP",
    "clip_group": "App Owned Group",
    "game": "Arc Raiders",
    "content_type": "Funny moment",
    "vibe": "Chaotic"
  }'::jsonb,
  'operator@example.invalid',
  'create',
  false
);

reset role;

truncate pg_temp.migration_036_second_claim;

set local role service_role;

insert into pg_temp.migration_036_second_claim
select *
from public.claim_pending_label_queue_exports(100);

reset role;

do $test$
begin
  if exists (
    select 1
    from pg_temp.migration_036_second_claim
    where buffer_post_id = 'MIGRATION_036_APP'
  ) or not exists (
    select 1
    from public.posts
    where buffer_post_id = 'MIGRATION_036_APP'
      and content_item_id is not null
      and label_queue_claim_token is null
  ) then
    raise exception 'Make claimed a row already owned by the app';
  end if;
end;
$test$;

revoke service_role
from current_user
granted by current_user;

revoke creator_analytics_web_labeler
from current_user
granted by current_user;

rollback;
