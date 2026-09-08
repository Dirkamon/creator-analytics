-- Insert before COMMIT. Every assertion failure rolls back the installation.
do $$ declare b record; r pg_roles%rowtype; d text; begin
  select * into strict b from pg_temp.preferences_rollout_before;
  if (select jsonb_agg(to_jsonb(p) order by buffer_post_id) from public.posts p) is distinct from b.posts
    or (select jsonb_agg(to_jsonb(p)-'preferences_revision'-'preferences_cadence' order by id) from public.schedule_change_proposals p) is distinct from b.proposals
    or (select jsonb_agg(to_jsonb(c) order by platform,content_format) from public.scheduling_cadence_settings c) is distinct from b.cadence then
    raise exception 'Posts, proposals or cadence changed; installation rolled back';
  end if;
  if (select jsonb_agg(to_jsonb(v) order by proposal_id) from public.schedule_change_application_preflight v) is distinct from b.preflight_rows then
    raise exception 'Disabled-path preflight results changed';
  end if;
  if (select jsonb_agg(to_jsonb(x) order by oid) from pg_roles x where rolname<>'creator_analytics_web_scheduler') is distinct from b.roles
    or (select jsonb_agg(to_jsonb(m) order by roleid,member,grantor) from pg_auth_members m
      where roleid<>'creator_analytics_web_scheduler'::regrole and member<>'creator_analytics_web_scheduler'::regrole) is distinct from b.memberships then
    raise exception 'Existing role attributes or memberships changed';
  end if;
  if exists(select 1 from pg_auth_members m
      where (roleid='creator_analytics_web_scheduler'::regrole or member='creator_analytics_web_scheduler'::regrole)
      and not (roleid='creator_analytics_web_scheduler'::regrole and pg_get_userbyid(member)='postgres'
        and pg_get_userbyid(grantor)='supabase_admin' and admin_option and not inherit_option and not set_option)) then
    raise exception 'Unexpected new settings role membership';
  end if;
  select * into strict r from pg_roles where rolname='creator_analytics_web_scheduler';
  if r.rolcanlogin or r.rolinherit or r.rolsuper or r.rolcreatedb or r.rolcreaterole or r.rolreplication or r.rolbypassrls
    or exists(select 1 from pg_authid where oid=r.oid and rolpassword is not null) then
    raise exception 'Settings account must remain restricted, NOLOGIN and passwordless';
  end if;
  if not exists(select 1 from public.scheduling_preferences where singleton and not enabled and revision=1
      and daily_floor=1 and max_shift_hours=12 and allowed_hours='all')
    or (select count(*) from public.scheduling_preferences)<>1
    or exists(select 1 from public.scheduling_preferences_audit)
    or exists(select 1 from public.scheduling_manual_baselines) then
    raise exception 'Unexpected preferences, audit entries or re-anchored existing posts';
  end if;
  if (select count(*) from creator_app.scheduling_preferences)<>2
    or (select count(*) from creator_app.scheduling_coverage)=0 then
    raise exception 'Incomplete settings or coverage views';
  end if;
  if exists(select 1 from pg_class where oid in ('public.scheduling_preferences'::regclass,
      'public.scheduling_preferences_audit'::regclass,'public.scheduling_manual_baselines'::regclass) and not relrowsecurity)
    or not has_table_privilege('creator_analytics_web_reader','creator_app.scheduling_preferences','SELECT')
    or not has_table_privilege('creator_analytics_web_reader','creator_app.scheduling_coverage','SELECT')
    or has_schema_privilege(r.oid,'public','CREATE') or has_schema_privilege(r.oid,'creator_app','USAGE,CREATE')
    or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','creator_app')
      and c.relkind in ('r','p','v','m','f') and has_table_privilege(r.oid,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')) then
    raise exception 'Unexpected restricted relation access';
  end if;
  if not has_function_privilege(r.oid,'public.save_scheduling_preferences(integer,integer,integer,integer,integer,boolean,text)','EXECUTE')
    or exists(select 1 from pg_proc p where p.pronamespace='public'::regnamespace and p.prorettype<>'trigger'::regtype
      and p.oid<>'public.save_scheduling_preferences(integer,integer,integer,integer,integer,boolean,text)'::regprocedure
      and has_function_privilege(r.oid,p.oid,'EXECUTE')) then
    raise exception 'Unexpected settings function access';
  end if;
  if md5(pg_get_viewdef('public.approved_schedule_changes_ready_to_apply'::regclass,true))<>'9cf0ede290b7d40fcc9073bc3abd3699'
    or (select jsonb_agg(jsonb_build_array(attnum,attname,atttypid,atttypmod) order by attnum) from pg_attribute
      where attrelid='public.approved_schedule_changes_ready_to_apply'::regclass and attnum>0 and not attisdropped) is distinct from b.make_columns
    or (select jsonb_build_object('oid',oid,'owner',proowner,'acl',proacl,'config',proconfig) from pg_proc
      where oid='public.create_collision_safe_schedule_proposals(integer,date,date)'::regprocedure) is distinct from b.generator_security then
    raise exception 'Make contract or generator identity/security changed';
  end if;
  d:=replace(pg_get_functiondef('public.create_collision_safe_schedule_proposals(integer,date,date)'::regprocedure),E'\r\n',E'\n');
  d:=replace(d,E'  -- Serialize preference dispatch before reading enabled state\n  perform pg_advisory_xact_lock(hashtextextended(''creator-analytics-schedule-proposal-generation'',0));\n','');
  d:=replace(d,E'  if (select enabled from public.scheduling_preferences where singleton) then\n    return public.create_preference_schedule_proposals(p_limit,p_start_date,p_end_date);\n  end if;\n','');
  if d is distinct from replace(b.generator,E'\r\n',E'\n') then
    raise exception 'Existing scheduler body changed beyond the reviewed opt-in dispatch';
  end if;
end $$;
