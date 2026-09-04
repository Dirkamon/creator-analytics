-- Creator Analytics
-- Add atomic ownership claims for Label Queue coexistence
-- File: Database/036_add_atomic_label_queue_export_claims.sql
--
-- Make must claim rows through claim_pending_label_queue_exports() before it
-- writes to Google Sheets. A claimed row cannot be labeled by the web app, and
-- a row labeled by the app cannot be claimed. Claims are intentionally not
-- reclaimed automatically: a Sheet write can succeed before its final marker,
-- so automatic retries could otherwise create duplicate Sheet rows.

begin;


-- ---------------------------------------------------------------------------
-- 1. Durable per-row ownership state
-- ---------------------------------------------------------------------------

alter table public.posts
  add column if not exists label_queue_claim_token uuid,
  add column if not exists label_queue_claimed_at timestamptz;

do $migration_036_constraint$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conrelid = 'public.posts'::regclass
      and constraint_record.conname = 'posts_label_queue_claim_pair_check'
  ) then
    alter table public.posts
      add constraint posts_label_queue_claim_pair_check
      check (
        (label_queue_claim_token is null)
        = (label_queue_claimed_at is null)
      );
  end if;
end;
$migration_036_constraint$;

create unique index if not exists posts_label_queue_claim_token_unique_idx
  on public.posts (label_queue_claim_token)
  where label_queue_claim_token is not null;

create index if not exists posts_label_queue_claimable_idx
  on public.posts (
    coalesce(sent_at, due_at, buffer_created_at),
    buffer_post_id
  )
  where content_item_id is null
    and label_queue_exported_at is null
    and label_queue_claim_token is null;


-- ---------------------------------------------------------------------------
-- 2. Forced claim/finalize protocol for the Make service role
-- ---------------------------------------------------------------------------

create or replace function public.claim_pending_label_queue_exports(
  p_limit integer default 100
)
returns table (
  claim_token uuid,
  buffer_post_id text,
  platform text,
  channel_name text,
  status text,
  post_text text,
  external_link text,
  published_at_local timestamp without time zone,
  publish_day_name text,
  publish_hour smallint,
  views bigint,
  reactions bigint,
  comments bigint,
  shares bigint,
  engagement_rate numeric,
  latest_metric_date date
)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception using
      errcode = '22023',
      message = 'Label Queue claim limit must be between 1 and 100';
  end if;

  return query
  with claimable as (
    select post_record.buffer_post_id
    from public.posts post_record
    where post_record.content_item_id is null
      and post_record.label_queue_exported_at is null
      and post_record.label_queue_claim_token is null
    order by
      coalesce(
        post_record.sent_at,
        post_record.due_at,
        post_record.buffer_created_at
      ) nulls last,
      post_record.buffer_post_id
    for update skip locked
    limit p_limit
  ), claimed as (
    update public.posts post_record
    set
      label_queue_claim_token = pg_catalog.gen_random_uuid(),
      label_queue_claimed_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
    from claimable
    where post_record.buffer_post_id = claimable.buffer_post_id
      and post_record.content_item_id is null
      and post_record.label_queue_exported_at is null
      and post_record.label_queue_claim_token is null
    returning
      post_record.buffer_post_id,
      post_record.label_queue_claim_token
  )
  select
    claimed.label_queue_claim_token,
    dashboard.buffer_post_id,
    dashboard.platform,
    dashboard.channel_name,
    dashboard.status,
    dashboard.post_text,
    dashboard.external_link,
    dashboard.published_at_local,
    dashboard.publish_day_name,
    dashboard.publish_hour,
    dashboard.views,
    dashboard.reactions,
    dashboard.comments,
    dashboard.shares,
    dashboard.engagement_rate,
    dashboard.latest_metric_date
  from claimed
  join public.dashboard_posts dashboard
    on dashboard.buffer_post_id = claimed.buffer_post_id
  order by
    dashboard.published_at_local nulls last,
    dashboard.buffer_post_id;
end;
$function$;

create or replace function public.mark_label_queue_exported(
  p_post_id text,
  p_claim_token uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_updated integer;
begin
  if p_post_id is null
     or pg_catalog.btrim(p_post_id) = ''
     or p_claim_token is null then
    raise exception using
      errcode = '22023',
      message = 'A post ID and its exact Label Queue claim token are required';
  end if;

  update public.posts
  set
    label_queue_exported_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where buffer_post_id = p_post_id
    and content_item_id is null
    and label_queue_exported_at is null
    and label_queue_claim_token = p_claim_token;

  get diagnostics v_updated = row_count;
  return v_updated = 1;
end;
$function$;

-- The former GET-then-mark contract is deliberately disabled for service_role.
-- This makes a stale Make scenario fail before it can present an unclaimed row
-- as successfully exported.
revoke select on public.pending_label_queue_exports
from service_role;

revoke execute on function public.mark_label_queue_exported(text)
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler;

revoke all on function public.claim_pending_label_queue_exports(integer)
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler;

revoke all on function public.mark_label_queue_exported(text, uuid)
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler;

grant execute on function public.claim_pending_label_queue_exports(integer)
to service_role;

grant execute on function public.mark_label_queue_exported(text, uuid)
to service_role;


-- ---------------------------------------------------------------------------
-- 3. Enforce the ownership boundary beneath every labeling entry point
-- ---------------------------------------------------------------------------

create or replace function public.prevent_claimed_label_queue_content_link()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if old.content_item_id is null
     and new.content_item_id is not null
     and old.label_queue_claim_token is not null
     and old.label_queue_exported_at is null then
    raise exception using
      errcode = 'P3007',
      message = 'The selected post is being exported by the Google Sheets workflow';
  end if;

  return new;
end;
$function$;

revoke execute on function public.prevent_claimed_label_queue_content_link()
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler;

drop trigger if exists posts_prevent_claimed_label_queue_content_link
  on public.posts;

create trigger posts_prevent_claimed_label_queue_content_link
before update of content_item_id on public.posts
for each row
execute function public.prevent_claimed_label_queue_content_link();


-- ---------------------------------------------------------------------------
-- 4. Expose claim state without exposing claim tokens to the web reader
-- ---------------------------------------------------------------------------

grant creator_analytics_web_view_owner
to current_user
with set true, inherit false;

set local role creator_analytics_web_view_owner;

-- Normalize the no-login owner's schema privileges as well. This repairs a
-- partially rolled-back/manual retry state without granting access to any
-- login role.
grant usage, create on schema creator_app
to creator_analytics_web_view_owner;

-- The private schema is owned by the no-login view owner. Temporarily grant
-- the migration session just enough schema access to replace the existing
-- SECURITY DEFINER helper after the owner drops its dependent view. Using
-- SESSION_USER is important here because CURRENT_USER is the view owner while
-- SET ROLE is active (including on hosted Supabase).
grant usage, create on schema creator_app
to session_user;

drop view creator_app.pending_label_queue_exports;

reset role;

drop function creator_app.read_pending_label_queue_exports();

create function creator_app.read_pending_label_queue_exports()
returns table (
  buffer_post_id text,
  queue_state text,
  claimed_at timestamp with time zone
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select
    post_record.buffer_post_id,
    case
      when post_record.label_queue_exported_at is not null
        then 'exported_unlinked'
      when post_record.label_queue_claim_token is not null
        then 'export_in_progress'
      else 'pending_export'
    end as queue_state,
    post_record.label_queue_claimed_at
  from public.posts post_record
  where post_record.content_item_id is null;
$function$;

revoke all on function creator_app.read_pending_label_queue_exports()
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_view_owner, creator_analytics_web_labeler;

grant execute on function creator_app.read_pending_label_queue_exports()
to creator_analytics_web_view_owner, creator_analytics_web_reader;

set local role creator_analytics_web_view_owner;

create view creator_app.pending_label_queue_exports
with (security_invoker = false, security_barrier = true)
as
select buffer_post_id, queue_state, claimed_at
from creator_app.read_pending_label_queue_exports();

revoke all on creator_app.pending_label_queue_exports
from public, anon, authenticated, service_role,
  creator_dashboard_reader, creator_analytics_web_reader,
  creator_analytics_web_labeler;

grant select on creator_app.pending_label_queue_exports
to creator_analytics_web_reader;

comment on view creator_app.pending_label_queue_exports is
'Server-only Label Queue ownership state. Claim tokens are deliberately omitted.';

revoke usage, create on schema creator_app
from session_user;

reset role;

revoke creator_analytics_web_view_owner
from current_user
granted by current_user;


-- ---------------------------------------------------------------------------
-- 5. Fail-closed postconditions
-- ---------------------------------------------------------------------------

do $migration_036_postconditions$
declare
  v_unexpected text;
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint constraint_record
    where constraint_record.conrelid = 'public.posts'::regclass
      and constraint_record.conname = 'posts_label_queue_claim_pair_check'
      and constraint_record.convalidated
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 036 claim-pair constraint is missing or invalid';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class index_relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = index_relation.relnamespace
    join pg_catalog.pg_index index_record
      on index_record.indexrelid = index_relation.oid
    where namespace.nspname = 'public'
      and index_relation.relname = 'posts_label_queue_claim_token_unique_idx'
      and index_record.indisunique
      and index_record.indisvalid
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 036 claim-token uniqueness is not enforced';
  end if;

  if pg_catalog.has_table_privilege(
       'service_role',
       'public.pending_label_queue_exports',
       'SELECT'
     )
     or pg_catalog.has_function_privilege(
       'service_role',
       'public.mark_label_queue_exported(text)',
       'EXECUTE'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 036 left the non-atomic Make contract available';
  end if;

  if not pg_catalog.has_function_privilege(
       'service_role',
       'public.claim_pending_label_queue_exports(integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'service_role',
       'public.mark_label_queue_exported(text,uuid)',
       'EXECUTE'
     ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 036 service role cannot execute the claim protocol';
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
      'claim_pending_label_queue_exports',
      'mark_label_queue_exported'
    )
    and function_record.oid::regprocedure::text <> 'mark_label_queue_exported(text)'
    and exists (
      select 1
      from pg_catalog.pg_roles role_record
      where role_record.rolname in (
        'anon', 'authenticated', 'creator_dashboard_reader',
        'creator_analytics_web_reader', 'creator_analytics_web_view_owner',
        'creator_analytics_web_labeler'
      )
        and pg_catalog.has_function_privilege(
          role_record.rolname,
          function_record.oid,
          'EXECUTE'
        )
    );

  if v_unexpected is not null then
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 036 claim function has an unexpected executor: %s',
        v_unexpected
      );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger trigger_record
    where trigger_record.tgrelid = 'public.posts'::regclass
      and trigger_record.tgname =
        'posts_prevent_claimed_label_queue_content_link'
      and not trigger_record.tgisinternal
      and trigger_record.tgenabled = 'O'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 036 labeling claim guard is not enabled';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    where namespace.nspname = 'creator_app'
      and relation.relname = 'pending_label_queue_exports'
      and relation.relkind = 'v'
      and pg_catalog.pg_get_userbyid(relation.relowner) =
        'creator_analytics_web_view_owner'
      and relation.reloptions @> array[
        'security_barrier=true',
        'security_invoker=false'
      ]::text[]
  ) then
    raise exception using
      errcode = '42501',
      message = 'Migration 036 private claim-state projection is not fail-closed';
  end if;
end;
$migration_036_postconditions$;

comment on column public.posts.label_queue_claim_token is
'Opaque per-row token proving that Make atomically claimed this Label Queue export.';

comment on column public.posts.label_queue_claimed_at is
'Time Make atomically claimed this Label Queue export; retained for diagnosis.';

comment on function public.claim_pending_label_queue_exports(integer) is
'Atomically claims unlabeled, unexported Label Queue rows for Make and returns their Sheet payload plus an opaque finalize token.';

comment on function public.mark_label_queue_exported(text, uuid) is
'Finalizes only the exact Label Queue row/token pair previously claimed by Make.';

commit;
