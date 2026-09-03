-- Creator Analytics
-- Add a controlled, server-only web labeling boundary
-- File: Database/035_add_controlled_web_labeling.sql
--
-- This migration adds a dedicated least-privilege login that can execute one
-- audited labeling function and nothing else. The function accepts only posts
-- that have not yet been exported to Google Sheets, so Make/Sheets remains the
-- single writer for rows already present in the fallback workflow.
--
-- No password is stored here. Provision the login only in staging until the
-- Phase 3 coexistence tests have passed.

begin;


-- ---------------------------------------------------------------------------
-- 1. Dedicated server-only labeler role
-- ---------------------------------------------------------------------------

do $migration_035_role$
begin
  if not exists (
    select 1
    from pg_catalog.pg_roles
    where rolname = 'creator_analytics_web_labeler'
  ) then
    create role creator_analytics_web_labeler
      login
      nosuperuser
      nocreatedb
      nocreaterole
      noinherit
      noreplication
      nobypassrls;
  end if;
end;
$migration_035_role$;

do $migration_035_role_safety$
declare
  v_unsafe text;
begin
  select role_record.rolname
  into v_unsafe
  from pg_catalog.pg_roles role_record
  where role_record.rolname = 'creator_analytics_web_labeler'
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
      message = 'Migration 035 refuses unsafe labeler role attributes';
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
  into v_unsafe
  from pg_catalog.pg_auth_members membership
  join pg_catalog.pg_roles granted_role
    on granted_role.oid = membership.roleid
  join pg_catalog.pg_roles member_role
    on member_role.oid = membership.member
  where member_role.rolname = 'creator_analytics_web_labeler'
     or (
       granted_role.rolname = 'creator_analytics_web_labeler'
       and not (
         member_role.rolname = current_user
         and membership.admin_option
         and not membership.inherit_option
         and not membership.set_option
       )
     );

  if v_unsafe is not null then
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 035 refuses unsafe labeler role memberships: %s',
        v_unsafe
      );
  end if;
end;
$migration_035_role_safety$;

alter role creator_analytics_web_labeler
  login
  noinherit;

alter role creator_analytics_web_labeler
  set statement_timeout = '15s';

alter role creator_analytics_web_labeler
  set idle_in_transaction_session_timeout = '15s';

alter role creator_analytics_web_labeler
  set search_path = pg_catalog;

grant connect on database postgres
to creator_analytics_web_labeler;

grant usage on schema public
to creator_analytics_web_labeler;


-- ---------------------------------------------------------------------------
-- 2. Minimal audit record and the single mutation function
-- ---------------------------------------------------------------------------

create table if not exists public.web_labeling_events (
  id bigint generated always as identity primary key,
  buffer_post_id text not null,
  content_item_id uuid not null,
  actor_email text not null,
  clip_group text not null,
  operation text not null
    check (operation in ('create', 'link_existing')),
  affected_post_count integer not null
    check (affected_post_count > 0),
  created_at timestamptz not null default now()
);

alter table public.web_labeling_events enable row level security;

create index if not exists web_labeling_events_post_created_idx
  on public.web_labeling_events (buffer_post_id, created_at desc);

-- Sheet imports normalize Clip Group names before inserting them. Enforce the
-- same identity rule for older or synthetic rows whose display case differs,
-- so a web submission cannot create a case-only duplicate.
create unique index if not exists content_items_internal_title_normalized_unique_idx
  on public.content_items (
    (pg_catalog.lower(pg_catalog.btrim(internal_title)))
  )
  where internal_title is not null
    and pg_catalog.btrim(internal_title) <> '';

revoke all on table public.web_labeling_events
from
  public,
  anon,
  authenticated,
  service_role,
  creator_dashboard_reader,
  creator_analytics_web_reader,
  creator_analytics_web_view_owner,
  creator_analytics_web_labeler;

-- A Make run that tries to mark a row after the app has already linked it must
-- fail closed instead of recording a misleading Sheet export timestamp. This
-- cannot detect an external row fetched before the transaction began, so the
-- web path remains staging-only until Make uses an atomic claim protocol.
create or replace function public.mark_label_queue_exported(
  p_post_id text
)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_updated integer;
begin
  update public.posts
  set
    label_queue_exported_at = now(),
    updated_at = now()
  where buffer_post_id = p_post_id
    and content_item_id is null
    and label_queue_exported_at is null;

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$function$;

revoke execute on function public.mark_label_queue_exported(text)
from public, anon, authenticated, creator_analytics_web_labeler;

grant execute on function public.mark_label_queue_exported(text)
to service_role;

create or replace function public.process_content_label_payload_for_web(
  p_payload jsonb,
  p_actor_email text,
  p_mode text,
  p_confirm_shared_effect boolean default false
)
returns table (
  result_content_item_id uuid,
  result_clip_group text,
  affected_post_count integer
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_post_id text;
  v_actor_email text;
  v_clip_group text;
  v_existing_clip_group text;
  v_mode text;
  v_content_item_id uuid;
  v_existing_content_item_id uuid;
  v_existing_post_content_item_id uuid;
  v_label_queue_exported_at timestamptz;
  v_game text;
  v_content_type text;
  v_vibe text;
  v_hook_type text;
  v_duration_seconds numeric;
  v_editing_intensity text;
  v_source_recording text;
  v_notes text;
  v_existing_post_count integer := 0;
  v_affected_post_count integer;
  v_effective_payload jsonb;
begin
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'The label payload must be a JSON object';
  end if;

  if p_payload - array[
    'post_id',
    'clip_group',
    'game',
    'content_type',
    'vibe',
    'hook_type',
    'duration_seconds',
    'editing_intensity',
    'source_recording',
    'notes'
  ]::text[] <> '{}'::jsonb then
    raise exception using
      errcode = '22023',
      message = 'The label payload contains unsupported fields';
  end if;

  v_post_id := pg_catalog.btrim(p_payload ->> 'post_id');
  v_actor_email := pg_catalog.lower(pg_catalog.btrim(p_actor_email));
  v_clip_group := pg_catalog.lower(pg_catalog.btrim(p_payload ->> 'clip_group'));
  v_mode := pg_catalog.lower(pg_catalog.btrim(p_mode));

  if coalesce(v_post_id, '') = ''
     or pg_catalog.length(v_post_id) > 255 then
    raise exception using
      errcode = '22023',
      message = 'A valid Buffer post ID is required';
  end if;

  if coalesce(v_actor_email, '') = ''
     or pg_catalog.length(v_actor_email) > 320
     or pg_catalog.strpos(v_actor_email, '@') = 0 then
    raise exception using
      errcode = '22023',
      message = 'A valid actor email is required';
  end if;

  if coalesce(v_clip_group, '') = ''
     or pg_catalog.length(v_clip_group) > 160 then
    raise exception using
      errcode = '22023',
      message = 'A valid Clip Group is required';
  end if;

  if v_mode not in ('create', 'link_existing') then
    raise exception using
      errcode = '22023',
      message = 'The label operation is not supported';
  end if;

  -- Serialize concurrent attempts for the same normalized Clip Group. This
  -- prevents two apparent "new" groups from silently becoming a shared edit.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_clip_group, 0)
  );

  select
    post_record.content_item_id,
    post_record.label_queue_exported_at
  into
    v_existing_post_content_item_id,
    v_label_queue_exported_at
  from public.posts post_record
  where post_record.buffer_post_id = v_post_id
  for update;

  if not found then
    raise exception using
      errcode = 'P3004',
      message = 'The selected post no longer exists';
  end if;

  if v_existing_post_content_item_id is not null then
    raise exception using
      errcode = 'P3001',
      message = 'The selected post is already labeled';
  end if;

  if v_label_queue_exported_at is not null then
    raise exception using
      errcode = 'P3002',
      message = 'The selected post is already owned by the Google Sheets workflow';
  end if;

  select
    content_item.id,
    content_item.internal_title,
    content_item.game,
    content_item.content_type,
    content_item.vibe,
    content_item.hook_type,
    content_item.duration_seconds,
    content_item.editing_intensity,
    content_item.source_recording,
    content_item.notes
  into
    v_existing_content_item_id,
    v_existing_clip_group,
    v_game,
    v_content_type,
    v_vibe,
    v_hook_type,
    v_duration_seconds,
    v_editing_intensity,
    v_source_recording,
    v_notes
  from public.content_items content_item
  where pg_catalog.lower(pg_catalog.btrim(content_item.internal_title))
    = v_clip_group
  for update;

  if v_existing_content_item_id is not null then
    select pg_catalog.count(*)::integer
    into v_existing_post_count
    from public.posts post_record
    where post_record.content_item_id = v_existing_content_item_id;
  end if;

  if v_mode = 'link_existing' then
    if v_existing_content_item_id is null then
      raise exception using
        errcode = 'P3006',
        message = 'The selected Clip Group no longer exists';
    end if;

    if not coalesce(p_confirm_shared_effect, false) then
      raise exception using
        errcode = 'P3003',
        message = 'Shared Clip Group confirmation is required';
    end if;

    -- Existing shared labels are authoritative. Ignore any client-supplied
    -- label values and link only the selected post. This direct link avoids
    -- the legacy helper's lower-casing behavior for older display-cased names.
    v_clip_group := v_existing_clip_group;
  else
    if v_existing_content_item_id is not null then
      raise exception using
        errcode = 'P3005',
        message = 'That Clip Group already exists';
    end if;

    v_game := pg_catalog.btrim(p_payload ->> 'game');
    v_content_type := pg_catalog.btrim(p_payload ->> 'content_type');
    v_vibe := pg_catalog.btrim(p_payload ->> 'vibe');
    v_hook_type := nullif(
      pg_catalog.btrim(p_payload ->> 'hook_type'),
      ''
    );
    v_editing_intensity := nullif(
      pg_catalog.btrim(p_payload ->> 'editing_intensity'),
      ''
    );
    v_source_recording := nullif(
      pg_catalog.btrim(p_payload ->> 'source_recording'),
      ''
    );
    v_notes := nullif(
      pg_catalog.btrim(p_payload ->> 'notes'),
      ''
    );

    if v_game is null or not v_game = any(array[
      'Rainbow Six Siege', 'RLCraft', 'Minecraft', 'Subnautica 2',
      'ARK Survival Evolved', 'Black Ops 3 Zombies', 'Ready or Not',
      'Arc Raiders', 'Escape the Backrooms', 'Terraria', 'Skyrim',
      'Marvel Rivals', 'REPO', 'Other', 'Battlefield',
      'Halo campaign evolved'
    ]::text[]) then
      raise exception using
        errcode = '22023',
        message = 'Game must use an approved Label Queue value';
    end if;

    if v_content_type is null or not v_content_type = any(array[
      'Squad banter', 'Fail', 'Clutch', 'Out-of-context', 'Funny moment',
      'Reaction', 'Story', 'Gameplay highlight', 'Gaming news', 'Tutorial',
      'Compilation', 'Other'
    ]::text[]) then
      raise exception using
        errcode = '22023',
        message = 'Content Type must use an approved Label Queue value';
    end if;

    if v_vibe is null or not v_vibe = any(array[
      'Funny', 'Chaotic', 'Casual', 'Intense', 'Dry/deadpan', 'Wholesome',
      'Frustrated', 'Informative'
    ]::text[]) then
      raise exception using
        errcode = '22023',
        message = 'Vibe must use an approved Label Queue value';
    end if;

    if v_hook_type is not null and not v_hook_type = any(array[
      'Immediate dialogue', 'Immediate action', 'Text setup', 'Question',
      'Reaction first', 'Slow setup', 'No explicit hook', 'Other'
    ]::text[]) then
      raise exception using
        errcode = '22023',
        message = 'Hook Type must use an approved Label Queue value';
    end if;

    if v_editing_intensity is not null
       and not v_editing_intensity = any(array[
         'Light', 'Medium', 'Heavy'
       ]::text[]) then
      raise exception using
        errcode = '22023',
        message = 'Editing Intensity must use an approved Label Queue value';
    end if;

    if coalesce(p_payload ->> 'duration_seconds', '') <> '' then
      if not (p_payload ->> 'duration_seconds') ~ '^[0-9]+$' then
        raise exception using
          errcode = '22023',
          message = 'Duration must be a whole number of seconds';
      end if;
      v_duration_seconds := (p_payload ->> 'duration_seconds')::numeric;
      if v_duration_seconds > 86400 then
        raise exception using
          errcode = '22023',
          message = 'Duration is outside the accepted range';
      end if;
    else
      v_duration_seconds := null;
    end if;

    if pg_catalog.length(coalesce(v_source_recording, '')) > 255
       or pg_catalog.length(coalesce(v_notes, '')) > 2000 then
      raise exception using
        errcode = '22023',
        message = 'An optional label field is too long';
    end if;

    v_effective_payload := pg_catalog.jsonb_build_object(
      'post_id', v_post_id,
      'clip_group', v_clip_group,
      'game', v_game,
      'content_type', v_content_type,
      'vibe', v_vibe,
      'hook_type', v_hook_type,
      'duration_seconds', v_duration_seconds,
      'editing_intensity', v_editing_intensity,
      'source_recording', v_source_recording,
      'notes', v_notes
    );
  end if;

  if v_mode = 'link_existing' then
    update public.posts
    set content_item_id = v_existing_content_item_id
    where buffer_post_id = v_post_id
      and content_item_id is null
      and label_queue_exported_at is null
    returning content_item_id
    into v_content_item_id;

    if v_content_item_id is null then
      raise exception using
        errcode = '40001',
        message = 'The selected post changed while it was being labeled';
    end if;
  else
    v_content_item_id := public.process_content_label_payload(
      v_effective_payload
    );
  end if;

  select pg_catalog.count(*)::integer
  into v_affected_post_count
  from public.posts post_record
  where post_record.content_item_id = v_content_item_id;

  insert into public.web_labeling_events (
    buffer_post_id,
    content_item_id,
    actor_email,
    clip_group,
    operation,
    affected_post_count
  )
  values (
    v_post_id,
    v_content_item_id,
    v_actor_email,
    v_clip_group,
    v_mode,
    v_affected_post_count
  );

  return query
  select
    v_content_item_id,
    v_clip_group,
    v_affected_post_count;
end;
$function$;

revoke all on function public.process_content_label_payload_for_web(
  jsonb, text, text, boolean
)
from
  public,
  anon,
  authenticated,
  service_role,
  creator_dashboard_reader,
  creator_analytics_web_reader,
  creator_analytics_web_view_owner;

grant execute on function public.process_content_label_payload_for_web(
  jsonb, text, text, boolean
)
to creator_analytics_web_labeler;


-- ---------------------------------------------------------------------------
-- 3. Add the one shared-label field required by the confirmation UI
-- ---------------------------------------------------------------------------

grant creator_analytics_web_view_owner
to current_user
with set true, inherit false;

set local role creator_analytics_web_view_owner;

create or replace view creator_app.looker_dashboard_posts
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
  calculated_interaction_rate,
  vibe
from public.looker_dashboard_posts;

reset role;

revoke creator_analytics_web_view_owner
from current_user
granted by current_user;


-- ---------------------------------------------------------------------------
-- 4. Fail-closed postconditions
-- ---------------------------------------------------------------------------

do $migration_035_postconditions$
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
    raise exception using
      errcode = '42501',
      message = 'Migration 035 labeler attributes are not fail-closed';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc function_record
    join pg_catalog.pg_namespace namespace
      on namespace.oid = function_record.pronamespace
    where namespace.nspname = 'public'
      and function_record.proname = 'process_content_label_payload_for_web'
      and function_record.prosecdef
      and function_record.provolatile = 'v'
      and pg_catalog.pg_get_userbyid(function_record.proowner) = current_user
      and function_record.proconfig @> array[
        'search_path=""'
      ]::text[]
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 035 labeling function is not fail-closed';
  end if;

  if not pg_catalog.has_function_privilege(
       'creator_analytics_web_labeler',
       'public.process_content_label_payload_for_web(jsonb,text,text,boolean)',
       'EXECUTE'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 035 labeler cannot execute its exact wrapper';
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
    raise exception using
      errcode = '42501',
      message = 'Migration 035 normalized Clip Group identity is not enforced';
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
      'mark_label_queue_exported',
      'refresh_schedule_proposals',
      'create_content_aware_schedule_proposals',
      'set_schedule_proposal_decision',
      'mark_schedule_proposal_exported',
      'mark_schedule_proposal_applied',
      'mark_schedule_proposal_error'
    )
    and pg_catalog.has_function_privilege(
      'creator_analytics_web_labeler',
      function_record.oid,
      'EXECUTE'
    );

  if v_unexpected is not null then
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 035 labeler can execute unrelated mutation functions: %s',
        v_unexpected
      );
  end if;

  if pg_catalog.has_table_privilege(
       'creator_analytics_web_labeler',
       'public.posts',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     )
     or pg_catalog.has_table_privilege(
       'creator_analytics_web_labeler',
       'public.content_items',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     )
     or pg_catalog.has_table_privilege(
       'creator_analytics_web_labeler',
       'public.web_labeling_events',
       'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 035 labeler received direct table access';
  end if;
end;
$migration_035_postconditions$;

comment on role creator_analytics_web_labeler is
'Restricted server-only login for the single audited Phase 3 labeling wrapper. Passwords are provisioned outside migrations.';

comment on table public.web_labeling_events is
'Audit trail for server-mediated web labels; never exposed to browser roles.';

comment on function public.process_content_label_payload_for_web(
  jsonb, text, text, boolean
) is
'Labels only not-yet-exported posts, preserves existing shared Clip Group labels, records the authorized operator, and leaves Sheets/Make ownership unchanged for exported rows.';

commit;
