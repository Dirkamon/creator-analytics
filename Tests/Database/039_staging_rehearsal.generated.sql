-- GENERATED from migration 039 + its regression. Regenerate after either changes.
-- APPROVAL REQUIRED: isolated hosted staging rehearsal; no production or Buffer.
-- Target: iepwctcayajdpvsmfmgl, Creator Analytics Staging. Verify browser breadcrumb.
-- Temporary data, role grants, functions, views, tables and settings all ROLLBACK.
-- Existing RLS is NOT disabled. Persistent tables created here explicitly enable it.
-- Scheduling preferences, opt-in only. Install/test in staging before rollout.
-- No external calls. Existing Make wrapper signatures and feed columns survive.
begin;
do $$ begin
  if to_regclass('public.scheduling_preferences') is not null
    or exists(select 1 from public.posts where buffer_post_id not like '__STAGING_DEMO__%')
    or (select count(*) from public.posts)<>25
    or (select count(*) from public.schedule_change_proposals)<>4 then
    raise exception 'Unexpected staging state; stop and re-audit';
  end if;
end $$;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table if not exists public.scheduling_preferences (
  singleton boolean primary key default true check (singleton),
  revision integer not null default 1 check (revision > 0),
  enabled boolean not null default false,
  daily_floor integer not null default 1 check (daily_floor = 1),
  max_shift_hours integer not null default 12 check (max_shift_hours = 12),
  allowed_hours text not null default 'all' check (allowed_hours = 'all'),
  updated_at timestamptz not null default now(),
  updated_by text
);
insert into public.scheduling_preferences(singleton) values(true) on conflict do nothing;
alter table public.scheduling_preferences enable row level security;

create table if not exists public.scheduling_manual_baselines (
  buffer_post_id text primary key references public.posts(buffer_post_id) on delete cascade,
  due_at timestamptz not null,
  captured_at timestamptz not null default now()
);
alter table public.scheduling_manual_baselines enable row level security;

-- History-free synchronized schedules are the only automatic baseline source.
-- Once a proposal exists, neither later syncs nor system-applied targets reanchor it.
create or replace function public.capture_scheduling_manual_baseline()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'scheduled' and new.due_at is not null
    and new.schedule_evaluated_at is null
    and not exists(select 1 from public.schedule_change_proposals h where h.buffer_post_id=new.buffer_post_id)
  then
    insert into public.scheduling_manual_baselines(buffer_post_id,due_at)
    values(new.buffer_post_id,new.due_at)
    on conflict(buffer_post_id) do update set due_at=excluded.due_at, captured_at=now()
      where scheduling_manual_baselines.due_at is distinct from excluded.due_at;
  end if;
  return new;
end;
$$;
drop trigger if exists capture_scheduling_manual_baseline on public.posts;
create trigger capture_scheduling_manual_baseline after insert or update of due_at,status on public.posts
for each row execute function public.capture_scheduling_manual_baseline();
insert into public.scheduling_manual_baselines(buffer_post_id,due_at)
select p.buffer_post_id,p.due_at from public.posts p
where p.status='scheduled' and p.due_at is not null and p.schedule_evaluated_at is null
  and not exists(select 1 from public.schedule_change_proposals h where h.buffer_post_id=p.buffer_post_id)
on conflict do nothing;

alter table public.schedule_change_proposals
  add column if not exists preferences_revision integer,
  add column if not exists preferences_cadence jsonb;

create table if not exists public.scheduling_preferences_audit (
  revision integer primary key,
  actor text not null,
  settings jsonb not null,
  changed_at timestamptz not null default now()
);
alter table public.scheduling_preferences_audit enable row level security;

do $$ begin
  if not exists(select 1 from pg_roles where rolname='creator_analytics_web_scheduler') then
    create role creator_analytics_web_scheduler nologin noinherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if exists(select 1 from pg_roles where rolname='creator_analytics_web_scheduler'
      and (rolsuper or rolcreatedb or rolcreaterole or rolreplication or rolbypassrls)) then
    raise exception 'Unsafe scheduling settings role';
  end if;
  if exists(select 1 from pg_auth_members where member='creator_analytics_web_scheduler'::regrole) then
    raise exception 'Scheduling settings role must not belong to other roles';
  end if;
end $$;
grant usage on schema public to creator_analytics_web_scheduler;
grant connect on database postgres to creator_analytics_web_scheduler;

create or replace function public.save_scheduling_preferences(
  p_expected_revision integer, p_tiktok_weekly integer, p_tiktok_ceiling integer,
  p_youtube_weekly integer, p_youtube_ceiling integer, p_enabled boolean, p_actor text
) returns integer language plpgsql security definer set search_path = '' as $$
declare v_revision integer;
begin
  if p_expected_revision is null or p_enabled is null
    or p_actor is null or length(btrim(p_actor)) not between 3 and 254
    or p_tiktok_weekly is null or p_youtube_weekly is null
    or p_tiktok_ceiling is null or p_youtube_ceiling is null
    or p_tiktok_ceiling not between 1 and 4 or p_youtube_ceiling not between 1 and 4
    or p_tiktok_weekly not between 7 and p_tiktok_ceiling*7
    or p_youtube_weekly not between 7 and p_youtube_ceiling*7 then
    raise exception using errcode='22023',message='Invalid scheduling preferences';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('creator-analytics-schedule-proposal-generation',0));
  select revision into strict v_revision from public.scheduling_preferences where singleton for update;
  if v_revision <> p_expected_revision then
    raise exception using errcode='P4101',message='Preferences changed; reload before saving';
  end if;
  -- Never silently stale an approval or reopen a historical scheduling cycle.
  if exists(select 1 from public.schedule_change_proposals where approval_status in ('Pending','Approved')) then
    raise exception using errcode='P4102',message='Resolve pending and approved proposals before changing preferences';
  end if;
  if (select count(*) from public.scheduling_cadence_settings
      where platform in ('tiktok','youtube') and content_format='short_form' and is_active)=2 then
    update public.scheduling_cadence_settings set
      posts_per_week=case platform when 'tiktok' then p_tiktok_weekly else p_youtube_weekly end,
      max_posts_per_day=case platform when 'tiktok' then p_tiktok_ceiling else p_youtube_ceiling end,
      updated_at=now()
    where platform in ('tiktok','youtube') and content_format='short_form';
  else
    raise exception 'Both supported short-form platforms must be configured and active';
  end if;
  update public.scheduling_preferences set revision=revision+1,enabled=p_enabled,updated_at=now(),updated_by=btrim(p_actor)
    where singleton returning revision into v_revision;
  insert into public.scheduling_preferences_audit(revision,actor,settings)
  values(v_revision,btrim(p_actor),jsonb_build_object('enabled',p_enabled,'tiktok_weekly',p_tiktok_weekly,
    'tiktok_ceiling',p_tiktok_ceiling,'youtube_weekly',p_youtube_weekly,'youtube_ceiling',p_youtube_ceiling,
    'max_shift_hours',12,'daily_floor',1,'allowed_hours','all'));
  return v_revision;
end;
$$;

-- One shared check is used at insertion, approval, and Make-feed read time.
create or replace function public.scheduling_preference_block(p public.schedule_change_proposals)
returns text language plpgsql stable security definer set search_path = '' as $$
declare s public.scheduling_preferences%rowtype; b timestamptz; c jsonb; channel_id text;
begin
  select * into strict s from public.scheduling_preferences where singleton;
  if not s.enabled then return null; end if;
  if p.preferences_revision is distinct from s.revision then return 'Blocked: scheduling preferences changed or proposal predates activation'; end if;
  select to_jsonb(x) into c from public.scheduling_cadence_settings x
    where x.platform=p.platform and x.content_format=p.content_format;
  if c is null or p.preferences_cadence is distinct from c then return 'Blocked: cadence changed after generation'; end if;
  if p.timezone_name is distinct from c->>'timezone_name' then return 'Blocked: proposal timezone differs from its saved cadence'; end if;
  select due_at into b from public.scheduling_manual_baselines where buffer_post_id=p.buffer_post_id;
  if b is null then return 'Blocked: manual Buffer time is unknown'; end if;
  if p.current_due_at_utc is distinct from b then return 'Blocked: current schedule differs from its manual baseline'; end if;
  if p.proposed_due_at_utc is null or not isfinite(p.proposed_due_at_utc)
    or abs(extract(epoch from(p.proposed_due_at_utc-b))) > s.max_shift_hours*3600 then
    return 'Blocked: proposed time exceeds the 12-hour rescheduling limit';
  end if;
  if (p.proposed_due_at_utc at time zone p.timezone_name)::date<>(b at time zone p.timezone_name)::date then
    select buffer_channel_id into channel_id from public.posts where buffer_post_id=p.buffer_post_id;
    if not exists (
      select 1 from public.posts x where x.buffer_channel_id=channel_id and x.buffer_post_id<>p.buffer_post_id
        and x.status='scheduled' and (x.due_at at time zone p.timezone_name)::date=(b at time zone p.timezone_name)::date
        and not exists(select 1 from public.schedule_change_proposals h where h.buffer_post_id=x.buffer_post_id
          and (h.approval_status in ('Pending','Approved') or
            (h.approval_status='Applied' and h.applied_at is not null and (x.last_synced_at is null or x.last_synced_at<h.applied_at)))
          and (h.proposed_due_at_utc at time zone p.timezone_name)::date<>(x.due_at at time zone p.timezone_name)::date)
    ) then return 'Blocked: moving this post would leave its original day without guaranteed coverage'; end if;
  end if;
  return null;
end;
$$;

create or replace function public.guard_scheduling_preferences()
returns trigger language plpgsql security definer set search_path = '' as $$
declare reason text;
begin
  if not (select enabled from public.scheduling_preferences where singleton) then return new; end if;
  if tg_op='INSERT' then
    select revision into new.preferences_revision from public.scheduling_preferences where singleton;
    select to_jsonb(c) into new.preferences_cadence from public.scheduling_cadence_settings c
      where c.platform=new.platform and c.content_format=new.content_format;
  elsif row(new.preferences_revision,new.preferences_cadence) is distinct from row(old.preferences_revision,old.preferences_cadence) then
    raise exception using errcode='P4103',message='Proposal preference snapshot is immutable';
  end if;
  if new.approval_status in ('Pending','Approved') then
    reason := public.scheduling_preference_block(new);
    if reason is not null then raise exception using errcode='P4103',message=reason; end if;
  end if;
  return new;
end;
$$;
drop trigger if exists zz_scheduling_preferences_guard on public.schedule_change_proposals;
create trigger zz_scheduling_preferences_guard before insert or update on public.schedule_change_proposals
for each row execute function public.guard_scheduling_preferences();

-- Preserve the complete prior preflight and its column ordering; append checks
-- to the existing diagnostic fields, so all dependent app/Make views see them.
do $wrap_preflight$
declare definition text; columns text;
begin
  definition:=pg_get_viewdef('public.schedule_change_application_preflight'::regclass,true);
  if position('scheduling_preference_block' in definition)=0 then
    select string_agg(case attname
      when 'blocking_reasons' then 'b.blocking_reasons || array_remove(array[x.reason]::text[],null) as blocking_reasons'
      when 'blocking_reason' then 'coalesce(b.blocking_reason,x.reason) as blocking_reason'
      when 'is_ready' then '(b.is_ready and x.reason is null) as is_ready'
      else format('b.%I',attname) end,',' order by attnum) into columns
    from pg_attribute where attrelid='public.schedule_change_application_preflight'::regclass and attnum>0 and not attisdropped;
    execute 'create or replace view public.schedule_change_application_preflight with (security_invoker=false) as with b as ('
      || rtrim(definition,E';\n ') || ') select ' || columns
      || ' from b join public.schedule_change_proposals p on p.id=b.proposal_id cross join lateral (select public.scheduling_preference_block(p) as reason) x';
  end if;
end;
$wrap_preflight$;

-- Day coverage is checked on the effective plan (one time per post). Original
-- schedules remain safety reservations, so any subset of approvals stays safe.
create or replace function public.create_preference_schedule_proposals(p_limit integer,p_start_date date,p_end_date date)
returns integer language plpgsql security definer set search_path = '' as $$
declare chosen record; n integer:=0;
begin
  if p_limit is not null and p_limit not between 1 and 500 then raise exception 'Invalid limit'; end if;
  if p_start_date is not null and p_end_date is not null and p_end_date<p_start_date then raise exception 'Invalid date range'; end if;
  perform pg_advisory_xact_lock(hashtextextended('creator-analytics-schedule-proposal-generation',0));
  if not (select enabled from public.scheduling_preferences where singleton) then raise exception 'Scheduling preferences are disabled'; end if;
  -- A reusable transaction-local workspace is never trusted from a caller.
  if to_regclass('pg_temp.preference_candidates') is not null then drop table pg_temp.preference_candidates; end if;
  if to_regclass('pg_temp.preference_effective') is not null then drop table pg_temp.preference_effective; end if;
  if to_regclass('pg_temp.preference_reservations') is not null then drop table pg_temp.preference_reservations; end if;
  if to_regclass('pg_temp.preference_coverage_sources') is not null then drop table pg_temp.preference_coverage_sources; end if;
  perform 1 from public.posts p where p.status='scheduled' order by p.buffer_post_id for update;
  create temporary table preference_reservations on commit drop as
  select distinct reservation_post_id,buffer_channel_id,reserved_at_utc from public.schedule_slot_reservations;
  create index on preference_reservations(buffer_channel_id,reserved_at_utc);
  create temporary table preference_effective on commit drop as
  select p.buffer_post_id,p.buffer_channel_id,coalesce(q.proposed_due_at_utc,p.due_at) as effective_at
  from public.posts p left join lateral (
    select h.proposed_due_at_utc from public.schedule_change_proposals h
    where h.buffer_post_id=p.buffer_post_id and (h.approval_status in ('Pending','Approved') or
      (h.approval_status='Applied' and h.applied_at is not null and (p.last_synced_at is null or p.last_synced_at<h.applied_at)))
    order by h.generated_at desc,h.id limit 1
  ) q on true where p.status='scheduled' and p.due_at is not null;
  -- An incoming proposal is NOT guaranteed coverage: it may be rejected while
  -- another is approved. Reserve one synchronized, non-outgoing post per day.
  create temporary table preference_coverage_sources on commit drop as
  select p.buffer_post_id,p.buffer_channel_id,p.due_at as effective_at
  from public.posts p join public.channels ch on ch.buffer_channel_id=p.buffer_channel_id
  join public.scheduling_cadence_settings c on c.platform=lower(btrim(ch.service)) and c.content_format='short_form'
  where p.status='scheduled' and p.due_at is not null and not exists (
    select 1 from public.schedule_change_proposals h where h.buffer_post_id=p.buffer_post_id
    and (h.approval_status in ('Pending','Approved') or
      (h.approval_status='Applied' and h.applied_at is not null and (p.last_synced_at is null or p.last_synced_at<h.applied_at)))
    and (h.proposed_due_at_utc at time zone c.timezone_name)::date<>(p.due_at at time zone c.timezone_name)::date
  );
  create temporary table preference_candidates on commit drop as
  with posts as materialized (
    select p.buffer_post_id,p.buffer_channel_id,p.post_text,p.external_link,p.due_at,
      s.*,to_jsonb(s) as cadence_snapshot,b.due_at as baseline,
      sh.content_publish_iso_day,sh.content_recommended_window
    from public.posts p
    join public.channels ch on ch.buffer_channel_id=p.buffer_channel_id
    join public.scheduling_cadence_settings s on s.platform=lower(btrim(ch.service)) and s.content_format='short_form'
    join public.scheduling_manual_baselines b on b.buffer_post_id=p.buffer_post_id and b.due_at=p.due_at
    join public.looker_content_aware_shadow_schedule sh on sh.buffer_post_id=p.buffer_post_id and sh.platform=s.platform
    where p.status='scheduled' and p.due_at is not null and p.schedule_evaluated_at is null
      and s.platform in ('tiktok','youtube') and s.is_active and s.posts_per_week>0
      and sh.labels_complete and s.timezone_name in(select name from pg_timezone_names)
      and p.due_at>now()+make_interval(hours=>s.protected_hours)
      and not exists(select 1 from public.schedule_change_proposals h where h.buffer_post_id=p.buffer_post_id)
  ), candidates as (
    select p.*,r.recommendation_rank,r.recommendation_score,r.confidence,r.post_count,r.metrics_status,
      (d.day::date + make_time(least(r.window_start_hour+2,r.window_end_hour),0,0)) at time zone p.timezone_name as target_at,
      (r.recommendation_score + case when r.publish_iso_day=p.content_publish_iso_day then 26 else 0 end
        + case when r.time_window=p.content_recommended_window then 22 else 0 end)::numeric as score
    from posts p
    cross join lateral generate_series(
      greatest((now() at time zone p.timezone_name)::date+2,coalesce(p_start_date,(now() at time zone p.timezone_name)::date+2))::timestamp,
      least((now() at time zone p.timezone_name)::date+23,coalesce(p_end_date,(now() at time zone p.timezone_name)::date+23))::timestamp,
      interval '1 day') d(day)
    join public.looker_joint_posting_recommendations r on r.platform=p.platform
      and r.publish_iso_day=extract(isodow from d.day)::integer
      and r.post_count>=p.minimum_sample_size and r.metrics_age_days<=p.metrics_freshness_limit_days
  )
  select * from candidates c where isfinite(c.baseline)
    and abs(extract(epoch from(c.target_at-c.baseline)))<=12*3600
    and c.target_at>now()+make_interval(hours=>c.protected_hours)
    and c.target_at is distinct from c.due_at;
  create index on preference_candidates(buffer_post_id);
  loop
    exit when p_limit is not null and n>=p_limit;
    -- Dynamic re-ranking fills an uncovered eligible day before optimizing extras.
    -- Do not empty a previously covered source day while filling another one.
    select c.* into chosen from pg_temp.preference_candidates c
    cross join lateral(select count(*) as n from pg_temp.preference_effective e
      where e.buffer_channel_id=c.buffer_channel_id and (e.effective_at at time zone c.timezone_name)::date=(c.target_at at time zone c.timezone_name)::date) target
    cross join lateral(select count(*) as n from pg_temp.preference_coverage_sources e
      where e.buffer_channel_id=c.buffer_channel_id and (e.effective_at at time zone c.timezone_name)::date=(c.due_at at time zone c.timezone_name)::date) source
    where ((c.due_at at time zone c.timezone_name)::date=(c.target_at at time zone c.timezone_name)::date or source.n>1)
      and not exists(select 1 from pg_temp.preference_reservations r
        where r.buffer_channel_id=c.buffer_channel_id and r.reservation_post_id<>c.buffer_post_id
          and r.reserved_at_utc>c.target_at-make_interval(hours=>c.min_gap_hours)
          and r.reserved_at_utc<c.target_at+make_interval(hours=>c.min_gap_hours))
      and (select count(*) from pg_temp.preference_reservations r
        where r.buffer_channel_id=c.buffer_channel_id and r.reservation_post_id<>c.buffer_post_id
          and (r.reserved_at_utc at time zone c.timezone_name)::date=(c.target_at at time zone c.timezone_name)::date)+1<=c.max_posts_per_day
      and (select count(*) from pg_temp.preference_reservations r
        where r.buffer_channel_id=c.buffer_channel_id and r.reservation_post_id<>c.buffer_post_id
          and date_trunc('week',r.reserved_at_utc at time zone c.timezone_name)=date_trunc('week',c.target_at at time zone c.timezone_name))+1<=c.posts_per_week
    order by (target.n=0) desc, c.score desc, abs(extract(epoch from(c.target_at-c.baseline))),c.target_at,c.buffer_post_id
    limit 1;
    exit when not found;
    insert into public.schedule_change_proposals(buffer_post_id,platform,content_format,post_text,external_link,
      current_due_at_utc,current_due_at_local,proposed_due_at_utc,proposed_due_at_local,slot_rank,
      source_recommendation_rank,recommendation_score,confidence,supporting_sample_size,metrics_status,timezone_name,approval_status)
    values(chosen.buffer_post_id,chosen.platform,chosen.content_format,chosen.post_text,chosen.external_link,
      chosen.due_at,chosen.due_at at time zone chosen.timezone_name,chosen.target_at,chosen.target_at at time zone chosen.timezone_name,n+1,
      chosen.recommendation_rank,chosen.recommendation_score,chosen.confidence,chosen.post_count,chosen.metrics_status,chosen.timezone_name,'Pending');
    update public.posts set schedule_evaluated_at=now() where buffer_post_id=chosen.buffer_post_id;
    update pg_temp.preference_effective set effective_at=chosen.target_at where buffer_post_id=chosen.buffer_post_id;
    if (chosen.target_at at time zone chosen.timezone_name)::date<>(chosen.due_at at time zone chosen.timezone_name)::date then
      delete from pg_temp.preference_coverage_sources where buffer_post_id=chosen.buffer_post_id;
    end if;
    insert into pg_temp.preference_reservations values(chosen.buffer_post_id,chosen.buffer_channel_id,chosen.target_at);
    delete from pg_temp.preference_candidates where buffer_post_id=chosen.buffer_post_id;
    n:=n+1;
  end loop;
  return n;
end;
$$;

-- Insert one opt-in dispatch ahead of the existing implementation, preserving
-- its OID, owner, ACL, signature, and complete disabled-path behavior.
do $dispatch$
declare d text;
begin
  d:=pg_get_functiondef('public.create_collision_safe_schedule_proposals(integer,date,date)'::regprocedure);
  d:=replace(d,E'\r\n',E'\n');
  if position('public.create_preference_schedule_proposals' in d)=0 then
    if position(E'begin\n' in d)=0 then raise exception 'Unexpected generator definition'; end if;
    d:=regexp_replace(d,E'begin\n',E'begin\n  if (select enabled from public.scheduling_preferences where singleton) then\n    return public.create_preference_schedule_proposals(p_limit,p_start_date,p_end_date);\n  end if;\n');
  end if;
  -- Choose the enabled/disabled path only after a concurrent settings save has
  -- committed. Both paths also take this transaction-reentrant lock internally.
  if position('-- Serialize preference dispatch before reading enabled state' in d)=0 then
    d:=regexp_replace(d,E'begin\n',E'begin\n  -- Serialize preference dispatch before reading enabled state\n  perform pg_advisory_xact_lock(hashtextextended(''creator-analytics-schedule-proposal-generation'',0));\n');
  end if;
  execute d;
end;
$dispatch$;

create or replace function public.read_scheduling_preferences()
returns table(platform text,content_format text,posts_per_week integer,max_posts_per_day integer,
  min_gap_hours integer,protected_hours integer,timezone_name text,revision integer,enabled boolean,
  daily_floor integer,max_shift_hours integer,allowed_hours text,updated_at timestamptz)
language sql stable security definer set search_path='' as $$
select c.platform,c.content_format,c.posts_per_week,c.max_posts_per_day,c.min_gap_hours,c.protected_hours,c.timezone_name,
  s.revision,s.enabled,s.daily_floor,s.max_shift_hours,s.allowed_hours,s.updated_at
from public.scheduling_cadence_settings c cross join public.scheduling_preferences s
where c.platform in ('tiktok','youtube') and c.content_format='short_form';
$$;

-- Normalize provider defaults on every new table/function; no shared writer.
do $acl$
declare f record; a record;
begin
  for f in select oid,oid::regprocedure as identity,proowner from pg_proc
    where pronamespace='public'::regnamespace and proname in ('capture_scheduling_manual_baseline',
      'save_scheduling_preferences','scheduling_preference_block','guard_scheduling_preferences','create_preference_schedule_proposals',
      'read_scheduling_preferences','read_scheduling_coverage')
  loop
    for a in select distinct x.grantee from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
      where p.oid=f.oid and x.grantee<>f.proowner
    loop
      execute format('revoke all on function %s from %s',f.identity,
        case when a.grantee=0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end);
    end loop;
  end loop;
end;
$acl$;
revoke all on public.scheduling_preferences,public.scheduling_manual_baselines,public.scheduling_preferences_audit
from public,anon,authenticated,service_role,creator_dashboard_reader,creator_analytics_web_reader,
  creator_analytics_web_labeler,creator_analytics_web_approver,creator_analytics_web_scheduler;
grant execute on function public.save_scheduling_preferences(integer,integer,integer,integer,integer,boolean,text)
to creator_analytics_web_scheduler;
-- Functions referenced inside views still need caller EXECUTE. This predicate
-- only returns a blocking reason; it cannot change settings or proposal state.
grant execute on function public.scheduling_preference_block(public.schedule_change_proposals)
to service_role,creator_dashboard_reader,creator_analytics_web_reader,creator_analytics_web_view_owner;

create or replace function public.read_scheduling_coverage()
returns table(buffer_channel_id text,platform text,timezone_name text,local_date date,
  scheduled_count integer,planned_count integer,coverage_note text)
language sql stable security definer set search_path='' as $$
with days as (
  select c.buffer_channel_id,s.platform,s.timezone_name,d.day::date as local_date
  from public.channels c join public.scheduling_cadence_settings s
    on s.platform=lower(btrim(c.service)) and s.content_format='short_form' and s.is_active
  cross join lateral generate_series((now() at time zone s.timezone_name)::date+2,
    (now() at time zone s.timezone_name)::date+23,interval '1 day') d(day)
  where s.platform in ('tiktok','youtube')
), effective as (
  select p.buffer_post_id,p.buffer_channel_id,p.due_at,
    coalesce(q.proposed_due_at_utc,p.due_at) as planned_at
  from public.posts p left join lateral (
    select proposed_due_at_utc from public.schedule_change_proposals h
    where h.buffer_post_id=p.buffer_post_id and (
      h.approval_status in ('Pending','Approved') or
      (h.approval_status='Applied' and h.applied_at is not null and (p.last_synced_at is null or p.last_synced_at<h.applied_at)))
    order by h.generated_at desc,h.id limit 1
  ) q on true where p.status='scheduled' and p.due_at is not null
)
select d.buffer_channel_id,d.platform,d.timezone_name,d.local_date,
  count(e.buffer_post_id) filter(where (e.due_at at time zone d.timezone_name)::date=d.local_date)::integer as scheduled_count,
  count(e.buffer_post_id) filter(where (e.planned_at at time zone d.timezone_name)::date=d.local_date)::integer as planned_count,
  case when count(e.buffer_post_id) filter(where (e.planned_at at time zone d.timezone_name)::date=d.local_date)=0
    then 'No planned post. An eligible clip, fresh analytics, and a safe slot within 12 hours of its Buffer time are required.'
    else null end::text as coverage_note
from days d left join effective e on e.buffer_channel_id=d.buffer_channel_id
group by d.buffer_channel_id,d.platform,d.timezone_name,d.local_date;
$$;
-- Normalize every provider default for this newly created read-only helper too.
do $$ declare a record; begin
  for a in select distinct x.grantee from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
    where p.oid='public.read_scheduling_coverage()'::regprocedure and x.grantee<>p.proowner loop
    execute format('revoke all on function public.read_scheduling_coverage() from %s',
      case when a.grantee=0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end);
  end loop;
end $$;
grant execute on function public.read_scheduling_preferences(),public.read_scheduling_coverage()
to creator_analytics_web_reader,creator_analytics_web_view_owner;

-- Follow the existing reporting-owner pattern; never grant the reader source
-- table access, or leave the deployment account with CREATE in creator_app.
grant creator_analytics_web_view_owner to current_user with set true,inherit false;
set local role creator_analytics_web_view_owner;
create or replace view creator_app.scheduling_preferences with(security_invoker=false,security_barrier=true) as
select platform,content_format,posts_per_week,max_posts_per_day,min_gap_hours,protected_hours,timezone_name,
  revision,enabled,daily_floor,max_shift_hours,allowed_hours,updated_at
from public.read_scheduling_preferences();
create or replace view creator_app.scheduling_coverage with(security_invoker=false,security_barrier=true) as
select buffer_channel_id,platform,timezone_name,local_date,scheduled_count,planned_count,coverage_note
from public.read_scheduling_coverage();
revoke all on creator_app.scheduling_preferences,creator_app.scheduling_coverage
from public,anon,authenticated,service_role,creator_dashboard_reader,creator_analytics_web_labeler,
  creator_analytics_web_approver,creator_analytics_web_scheduler;
grant select on creator_app.scheduling_preferences,creator_app.scheduling_coverage to creator_analytics_web_reader;
reset role;
revoke creator_analytics_web_view_owner from current_user granted by current_user;

notify pgrst,'reload schema';

-- Real PostgreSQL integration tests. All fixtures and settings roll back.
-- Continue the migration transaction; final ROLLBACK removes everything.
set local statement_timeout='90s';
set local lock_timeout='5s';
set local timezone='UTC';
-- Hosted postgres is not a superuser. Temporary impersonation grants are part
-- of this rollback-only test, never part of the installed migration.
grant creator_analytics_web_reader,creator_analytics_web_scheduler to current_user with set true,inherit false;
create temporary table preferences_before on commit drop as
select (select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.buffer_post_id)::text,'')) from public.posts p) as posts,
  (select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.id)::text,'')) from public.schedule_change_proposals p) as proposals;

do $$ declare r text; begin
  foreach r in array array['anon','authenticated','creator_analytics_web_reader','creator_analytics_web_labeler','creator_analytics_web_approver','service_role'] loop
    if has_function_privilege(r,'public.save_scheduling_preferences(integer,integer,integer,integer,integer,boolean,text)','EXECUTE')
      or has_function_privilege(r,'public.create_preference_schedule_proposals(integer,date,date)','EXECUTE')
      or has_table_privilege(r,'public.scheduling_preferences','UPDATE') then raise exception 'Excess scheduling access: %',r; end if;
  end loop;
  if not has_function_privilege('creator_analytics_web_scheduler','public.save_scheduling_preferences(integer,integer,integer,integer,integer,boolean,text)','EXECUTE') then raise exception 'Missing narrow writer'; end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='approved_schedule_changes_ready_to_apply')<>19 then raise exception 'Make contract changed'; end if;
end $$;
savepoint preferences_fixture;
insert into public.organizations(buffer_organization_id,name) values('__039_ORG__','Preferences test');
insert into public.channels(buffer_channel_id,buffer_organization_id,service,name,timezone)
values('__039_TT__','__039_ORG__','tiktok','Preferences test TikTok','America/Denver'),
 ('__039_YT__','__039_ORG__','youtube','Preferences test YouTube','America/Denver');
insert into public.content_items(id,internal_title,game,content_type,vibe,hook_type)
values('03900000-0000-4000-8000-000000000001','Test clip','Preferences Test Game','Highlight','Funny','Surprise');
-- Fresh, evidence-backed historical observations across every day/window.
insert into public.posts(buffer_post_id,buffer_organization_id,buffer_channel_id,channel_service,
  content_item_id,post_text,status,due_at,sent_at,last_synced_at)
select '__039_HIST_'||platform||'_'||d||'_'||h||'_'||sample,'__039_ORG__',channel,platform,
 '03900000-0000-4000-8000-000000000001','Test historical clip','sent',
 ((date_trunc('week',now() at time zone 'America/Denver')::date-7*sample+d)+make_time(h,0,0)) at time zone 'America/Denver',
 ((date_trunc('week',now() at time zone 'America/Denver')::date-7*sample+d)+make_time(h,0,0)) at time zone 'America/Denver',now()
from (values('tiktok','__039_TT__'),('youtube','__039_YT__')) p(platform,channel)
cross join generate_series(0,6) d cross join generate_series(2,22,4) h cross join generate_series(1,3) sample;
insert into public.post_metric_snapshots(buffer_post_id,captured_on,captured_at,views,reactions,comments,shares)
select p.buffer_post_id,(now() at time zone 'America/Denver')::date,now(),2000+extract(hour from p.sent_at)::integer*100,100,10,5
from public.posts p where left(p.buffer_post_id,11)='__039_HIST_';
-- Two manually scheduled posts per day, all safely outside the current runway.
insert into public.posts(buffer_post_id,buffer_organization_id,buffer_channel_id,channel_service,
  content_item_id,post_text,status,due_at,last_synced_at)
select '__039_NEW_'||platform||'_'||d||'_'||h,'__039_ORG__',channel,platform,
 '03900000-0000-4000-8000-000000000001','Test queued clip','scheduled',
 ((date_trunc('week',now() at time zone 'America/Denver')::date+14+d)+make_time(h,0,0)) at time zone 'America/Denver',now()
from (values('tiktok','__039_TT__'),('youtube','__039_YT__')) p(platform,channel)
cross join generate_series(0,6) d cross join (values(8),(20)) hours(h);

-- Never enable globally via the writer while another proposal awaits a decision.
-- Owner-only fixture switch is rolled back; production is not involved.
update public.scheduling_preferences set enabled=true,revision=revision+1;
savepoint fresh_inventory;
do $$ declare n integer; again integer; begin
  if (select count(*) from public.scheduling_manual_baselines where buffer_post_id like '__039_NEW_%')<>28 then raise exception 'Baseline capture failed'; end if;
  if (select count(*) from public.looker_joint_posting_recommendations where post_count>=3 and metrics_age_days<=2)<42 then raise exception 'Recommendation fixture invalid'; end if;
  n:=public.refresh_schedule_proposals((date_trunc('week',now() at time zone 'America/Denver')::date+14),7);
  if n<2 then raise exception 'Expected real proposals for both platforms, got %',n; end if;
  if exists(select 1 from public.schedule_change_proposals p where p.buffer_post_id like '__039_NEW_%'
    and (abs(extract(epoch from(p.proposed_due_at_utc-p.current_due_at_utc)))>43200 or p.approval_status<>'Pending'
      or p.preferences_revision is null or p.preferences_cadence is null)) then raise exception 'Unsafe generated proposal'; end if;
  again:=public.refresh_schedule_proposals((date_trunc('week',now() at time zone 'America/Denver')::date+14),7);
  if again<>0 then raise exception 'Repeat generated % unexpected proposals',again; end if;
end $$;

savepoint generated;
-- Exercise the actual Make and reader roles, not just the database owner.
set local role service_role;
select count(*) as make_readable from public.approved_schedule_changes_ready_to_apply;
reset role;
set local role creator_analytics_web_reader;
select count(*) as preferences_readable from creator_app.scheduling_preferences;
select count(*) as coverage_readable from creator_app.scheduling_coverage;
reset role;
do $$ declare p public.schedule_change_proposals%rowtype; v_revision integer; blocked boolean:=false; begin
  select * into strict p from public.schedule_change_proposals where buffer_post_id like '__039_NEW_%' order by id limit 1;
  select revision into v_revision from public.scheduling_preferences where singleton;
  begin
    perform public.save_scheduling_preferences(v_revision,14,3,14,3,true,'test@example.invalid');
  exception when sqlstate 'P4102' then blocked:=true; end;
  if not blocked then raise exception 'Changed settings with unresolved proposals'; end if;
  -- Exact boundaries accepted by shared validator; one second farther rejected.
  p.proposed_due_at_utc:=p.current_due_at_utc+interval '12 hours';
  if public.scheduling_preference_block(p) is not null then raise exception 'Positive boundary rejected'; end if;
  p.proposed_due_at_utc:=p.current_due_at_utc-interval '12 hours';
  if public.scheduling_preference_block(p) is not null then raise exception 'Negative boundary rejected'; end if;
  p.proposed_due_at_utc:=p.current_due_at_utc-interval '12 hours 1 second';
  if public.scheduling_preference_block(p) is null then raise exception 'Outside boundary accepted'; end if;
  p.proposed_due_at_utc:=p.current_due_at_utc+interval '12 hours 1 second';
  if public.scheduling_preference_block(p) is null then raise exception 'Outside positive boundary accepted'; end if;
end $$;
do $$ declare p public.schedule_change_proposals%rowtype; failed boolean:=false; begin
  select * into strict p from public.schedule_change_proposals where buffer_post_id like '__039_NEW_%' order by id limit 1;
  update public.schedule_change_proposals set approval_status='Approved',approved_at=now() where id=p.id;
  if not exists(select 1 from public.approved_schedule_changes_ready_to_apply where proposal_id=p.id) then raise exception 'Safe approved proposal missing from Make feed'; end if;
  update public.scheduling_preferences set revision=revision+1;
  if exists(select 1 from public.approved_schedule_changes_ready_to_apply where proposal_id=p.id) then raise exception 'Stale settings bypassed Make gate'; end if;
  begin update public.schedule_change_proposals set approval_status='Approved' where id=p.id;
  exception when sqlstate 'P4103' then failed:=true; end;
  if not failed then raise exception 'Stale settings bypassed approval guard'; end if;
end $$;
rollback to generated;
do $$ declare p public.schedule_change_proposals%rowtype; b timestamptz; begin
  select * into strict p from public.schedule_change_proposals where buffer_post_id like '__039_NEW_%' order by id limit 1;
  select due_at into b from public.scheduling_manual_baselines where buffer_post_id=p.buffer_post_id;
  update public.posts set due_at=p.proposed_due_at_utc,last_synced_at=now() where buffer_post_id=p.buffer_post_id;
  if (select due_at from public.scheduling_manual_baselines where buffer_post_id=p.buffer_post_id) is distinct from b then raise exception 'Sync reanchored original time'; end if;
  update public.schedule_change_proposals set approval_status='Approved',approved_at=now() where id=p.id;
  if exists(select 1 from public.approved_schedule_changes_ready_to_apply where proposal_id=p.id) then raise exception 'Changed current time bypassed preflight'; end if;
end $$;
rollback to generated;
rollback to fresh_inventory;
-- An adjacent empty day gets priority, without emptying its source day.
update public.posts set status='draft' where buffer_post_id in ('__039_NEW_tiktok_1_8','__039_NEW_tiktok_1_20');
do $$ declare n integer; begin
  n:=public.refresh_schedule_proposals((date_trunc('week',now() at time zone 'America/Denver')::date+14),7);
  if not exists(select 1 from public.schedule_change_proposals where buffer_post_id='__039_NEW_tiktok_0_20'
    and proposed_due_at_local::date=date_trunc('week',now() at time zone 'America/Denver')::date+15) then
    raise exception 'Did not fill the adjacent uncovered day first'; end if;
  if exists(select 1 from creator_app.scheduling_coverage where buffer_channel_id='__039_TT__'
    and local_date=date_trunc('week',now() at time zone 'America/Denver')::date+14 and planned_count<1) then
    raise exception 'Emptied source day'; end if;
  update public.posts set status='draft' where buffer_post_id='__039_NEW_tiktok_0_8';
  if exists(select 1 from public.schedule_change_proposals p where p.buffer_post_id='__039_NEW_tiktok_0_20'
    and public.scheduling_preference_block(p) is null) then
    raise exception 'Approval/apply gate failed to recheck lost source-day coverage'; end if;
end $$;
rollback to fresh_inventory;
-- Any subset of approvals preserves spacing, capacity, and already covered days.
-- Use a smaller inventory so several independent proposals can be explored.
update public.posts set status='draft' where buffer_post_id like '__039_NEW_%' and buffer_post_id like '%_20';
select public.refresh_schedule_proposals(date_trunc('week',now() at time zone 'America/Denver')::date+14,7);
do $$ declare mask integer; total integer; begin
  select count(*) into total from public.schedule_change_proposals where buffer_post_id like '__039_NEW_%';
  if total<2 or total>14 then raise exception 'Invalid subset fixture: % proposals',total; end if;
  -- Same-day proposals cannot remove daily coverage. Check every subset for one
  -- platform (at most seven proposals), including mixtures of old/new times.
  select count(*) into total from public.schedule_change_proposals where buffer_post_id like '__039_NEW_tiktok_%';
  for mask in 0..(1<<total)-1 loop
    if exists(with q as (
      select buffer_post_id,proposed_due_at_utc,(row_number() over(order by id)-1)::integer as bit
      from public.schedule_change_proposals where buffer_post_id like '__039_NEW_tiktok_%'
    ), effective as (
      select case when (mask & (1<<q.bit))<>0 then q.proposed_due_at_utc else p.due_at end as at_time
      from public.posts p left join q using(buffer_post_id)
      where p.buffer_post_id like '__039_NEW_tiktok_%' and p.status='scheduled'
    ), spaced as (select at_time,lag(at_time) over(order by at_time) as prior from effective)
    select 1 from spaced where at_time-prior<interval '6 hours'
    union all select 1 from effective group by (at_time at time zone 'America/Denver')::date having count(*)>3
    union all select 1 from effective group by date_trunc('week',at_time at time zone 'America/Denver') having count(*)>14
    union all select 1 from public.posts original where original.buffer_post_id like '__039_NEW_tiktok_%' and original.status='scheduled'
      and not exists(select 1 from effective e where (e.at_time at time zone 'America/Denver')::date=(original.due_at at time zone 'America/Denver')::date)
    ) then raise exception 'Unsafe approval subset: %',mask; end if;
  end loop;
end $$;
rollback to fresh_inventory;
-- Entire candidate population is outside the requested range/movement windows.
do $$ begin
  if public.refresh_schedule_proposals((date_trunc('week',now() at time zone 'America/Denver')::date+24),1)<>0 then raise exception 'Ignored date/movement bounds'; end if;
end $$;
rollback to fresh_inventory;
update public.posts set status='draft' where buffer_post_id like '__039_NEW_%';
do $$ begin
  if public.refresh_schedule_proposals((date_trunc('week',now() at time zone 'America/Denver')::date+14),7)<>0 then raise exception 'Created proposals without stock'; end if;
end $$;
rollback to fresh_inventory;
update public.post_metric_snapshots set captured_on=captured_on-10 where buffer_post_id like '__039_HIST_%';
do $$ begin
  if public.refresh_schedule_proposals((date_trunc('week',now() at time zone 'America/Denver')::date+14),7)<>0 then raise exception 'Used stale evidence'; end if;
end $$;
rollback to preferences_fixture;
-- DST measures elapsed UTC hours, not clock labels. Spring-forward and fall-back.
do $$ begin
  if extract(epoch from ('2026-03-08 14:00 America/Denver'::timestamptz-'2026-03-08 01:00 America/Denver'::timestamptz))<>43200
    or extract(epoch from ('2026-11-01 12:00 America/Denver'::timestamptz-'2026-11-01 01:00-06'::timestamptz))<>43200 then
    raise exception 'DST fixture invalid'; end if;
end $$;
do $$ declare v integer; rejected boolean:=false; begin
  select revision into v from public.scheduling_preferences where singleton;
  begin perform public.save_scheduling_preferences(v,6,3,14,3,false,'test@example.invalid');
  exception when sqlstate '22023' then rejected:=true; end;
  if not rejected then raise exception 'Invalid weekly floor accepted'; end if;
end $$;
-- The real narrow writer can save and audit; a stale revision cannot overwrite.
savepoint writer_test;
update public.schedule_change_proposals set approval_status='Rejected' where approval_status in ('Pending','Approved');
create temporary table preference_expected as select revision from public.scheduling_preferences;
grant select on preference_expected to creator_analytics_web_scheduler;
set local role creator_analytics_web_scheduler;
select public.save_scheduling_preferences((select revision from preference_expected),14,3,14,3,false,'test@example.invalid') as saved_revision;
do $$ declare blocked boolean:=false; begin
  begin perform public.save_scheduling_preferences((select revision from preference_expected),14,3,14,3,false,'test@example.invalid');
  exception when sqlstate 'P4101' then blocked:=true; end;
  if not blocked then raise exception 'Stale save overwrote settings'; end if;
end $$;
reset role;
do $$ begin
  if not exists(select 1 from public.scheduling_preferences_audit where revision=(select revision+1 from preference_expected)
    and actor='test@example.invalid') then raise exception 'Missing save audit'; end if;
end $$;
rollback to writer_test;
do $$ begin
  if (select posts from preferences_before) is distinct from (select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.buffer_post_id)::text,'')) from public.posts p)
    or (select proposals from preferences_before) is distinct from (select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.id)::text,'')) from public.schedule_change_proposals p) then
    raise exception 'Existing records changed during rollback-only test'; end if;
end $$;
select 'PASS: preference ACLs, real generation, both 12-hour boundaries, repeat runs, approval/Make gates, immutable baseline, validation; fixtures rolled back' as result;
rollback;


select jsonb_build_object('preferences_installed',to_regclass('public.scheduling_preferences') is not null,'new_role_exists',exists(select 1 from pg_roles where rolname='creator_analytics_web_scheduler'),'posts',(select count(*) from public.posts),'proposals',(select count(*) from public.schedule_change_proposals),'make_contract',md5(pg_get_viewdef('public.approved_schedule_changes_ready_to_apply'::regclass,true))) as after_rollback;
