-- Insert inside migration 039's transaction, before any schema changes.
-- User approved installation with rules OFF, not activation or rescheduling.
do $$ begin
  if current_user <> 'postgres' or current_database() <> 'postgres' then
    raise exception 'Unexpected deployment identity';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('creator-analytics-schedule-proposal-generation',0)) then
    raise exception 'Scheduler is busy; no installation performed';
  end if;
end $$;
lock table public.posts,public.schedule_change_proposals,public.scheduling_cadence_settings in share row exclusive mode;
do $$ begin
  if to_regclass('public.scheduling_preferences') is not null
    or to_regclass('public.scheduling_manual_baselines') is not null
    or to_regclass('public.scheduling_preferences_audit') is not null
    or exists(select 1 from pg_roles where rolname='creator_analytics_web_scheduler') then
    raise exception 'Preferences or settings role already present; do not reinstall';
  end if;
  if (select count(*) from public.posts where status='scheduled')<>16
    or (select count(*) from public.posts where status='sent')<>1028
    or exists(select 1 from public.posts where buffer_post_id like '__STAGING_DEMO__%')
    or exists(select 1 from public.posts where label_queue_claim_token is not null)
    or exists(select 1 from public.schedule_change_proposals where approval_status in ('Pending','Approved') or sheet_export_claim_token is not null)
    or (select count(*) from public.schedule_change_proposals where approval_status='Applied')<>87
    or (select count(*) from public.schedule_change_proposals where approval_status='Rejected')<>36
    or (select count(*) from public.schedule_change_proposals)<>123 then
    raise exception 'Production work changed; stop and reconcile before installation';
  end if;
  if exists(select 1 from public.posts p where status='scheduled' and (
      content_item_id is null or not exists(select 1 from public.schedule_change_proposals h
        where h.buffer_post_id=p.buffer_post_id and h.approval_status='Applied'
          and h.applied_at is not null and p.last_synced_at>=h.applied_at and p.due_at=h.proposed_due_at_utc))) then
    raise exception 'An existing scheduled post is not reconciled';
  end if;
  if md5(pg_get_viewdef('public.approved_schedule_changes_ready_to_apply'::regclass,true))<>'9cf0ede290b7d40fcc9073bc3abd3699'
    or md5(pg_get_functiondef('public.create_collision_safe_schedule_proposals(integer,date,date)'::regprocedure))<>'f6adbc965d2f8a6ae2c29bf047bf5dbe' then
    raise exception 'Existing scheduler or Make contract changed';
  end if;
end $$;
create temporary table preferences_rollout_before on commit drop as select
  (select jsonb_agg(to_jsonb(p) order by buffer_post_id) from public.posts p) as posts,
  (select jsonb_agg(to_jsonb(p) order by id) from public.schedule_change_proposals p) as proposals,
  (select jsonb_agg(to_jsonb(c) order by platform,content_format) from public.scheduling_cadence_settings c) as cadence,
  (select jsonb_agg(to_jsonb(r) order by oid) from pg_roles r) as roles,
  (select jsonb_agg(to_jsonb(m) order by roleid,member,grantor) from pg_auth_members m) as memberships,
  (select jsonb_agg(to_jsonb(v) order by proposal_id) from public.schedule_change_application_preflight v) as preflight_rows,
  (select jsonb_agg(jsonb_build_array(attnum,attname,atttypid,atttypmod) order by attnum) from pg_attribute
    where attrelid='public.approved_schedule_changes_ready_to_apply'::regclass and attnum>0 and not attisdropped) as make_columns,
  (select jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl,'config',proconfig) from pg_proc
    where oid='public.create_collision_safe_schedule_proposals(integer,date,date)'::regprocedure) as generator_security,
  pg_get_functiondef('public.create_collision_safe_schedule_proposals(integer,date,date)'::regprocedure) as generator;
-- Defense in depth for the transaction-local comparison table as well.
alter table preferences_rollout_before enable row level security;
