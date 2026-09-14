-- Real PostgreSQL integration tests. All fixtures and settings roll back.
begin;
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
