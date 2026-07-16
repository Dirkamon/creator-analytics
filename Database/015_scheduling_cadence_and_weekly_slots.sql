-- Creator Analytics
-- Editable cadence settings and weekly slot allocation
-- File: Database/015_scheduling_cadence_and_weekly_slots.sql
--
-- Creates:
--   1. Editable scheduling cadence settings.
--   2. A safe, ranked weekly slot-allocation function.
--   3. Data Studio-ready views for cadence and the generated weekly template.
--
-- Initial settings:
--   TikTok short-form:       14 posts/week
--   YouTube short-form:      14 posts/week
--   YouTube long-form:       manual/inactive
--   Maximum:                 3 posts/platform/day
--   Minimum same-platform gap: 6 hours
--   Protected scheduling window: 24 hours
--
-- This migration does NOT change anything in Buffer.
-- Safe to rerun.

begin;

create table if not exists public.scheduling_cadence_settings (
  platform text not null,
  content_format text not null default 'short_form',
  posts_per_week integer not null default 0
    check (posts_per_week between 0 and 100),
  max_posts_per_day integer not null default 3
    check (max_posts_per_day between 1 and 10),
  min_gap_hours integer not null default 6
    check (min_gap_hours between 1 and 48),
  protected_hours integer not null default 24
    check (protected_hours between 0 and 168),
  minimum_sample_size integer not null default 3
    check (minimum_sample_size between 1 and 1000),
  metrics_freshness_limit_days integer not null default 2
    check (metrics_freshness_limit_days between 0 and 30),
  timezone_name text not null default 'America/Denver',
  is_active boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (platform, content_format)
);

alter table public.scheduling_cadence_settings
  enable row level security;

insert into public.scheduling_cadence_settings (
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
)
values
  (
    'tiktok',
    'short_form',
    14,
    3,
    6,
    24,
    3,
    2,
    'America/Denver',
    true,
    now()
  ),
  (
    'youtube',
    'short_form',
    14,
    3,
    4,
    24,
    3,
    2,
    'America/Denver',
    true,
    now()
  ),
  (
    'youtube',
    'long_form',
    0,
    1,
    24,
    48,
    3,
    2,
    'America/Denver',
    false,
    now()
  )
on conflict (platform, content_format)
do update set
  posts_per_week = excluded.posts_per_week,
  max_posts_per_day = excluded.max_posts_per_day,
  min_gap_hours = excluded.min_gap_hours,
  protected_hours = excluded.protected_hours,
  minimum_sample_size = excluded.minimum_sample_size,
  metrics_freshness_limit_days = excluded.metrics_freshness_limit_days,
  timezone_name = excluded.timezone_name,
  is_active = excluded.is_active,
  updated_at = now();


create or replace function public.generate_weekly_slot_plan(
  p_platform text,
  p_content_format text default 'short_form'
)
returns table (
  platform text,
  content_format text,
  slot_rank integer,
  source_recommendation_rank integer,
  publish_iso_day integer,
  publish_day_name text,
  scheduled_hour_local integer,
  scheduled_time_local time without time zone,
  recommended_window text,
  recommendation_score numeric,
  confidence text,
  supporting_sample_size integer,
  metrics_status text,
  timezone_name text,
  slot_key text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings public.scheduling_cadence_settings%rowtype;
  v_candidate record;
  v_selected_days integer[] := array[]::integer[];
  v_selected_week_hours integer[] := array[]::integer[];
  v_selected_count integer := 0;
  v_day_count integer;
  v_gap_ok boolean;
  v_slot_hour integer;
  v_week_hour integer;
begin
  select *
  into v_settings
  from public.scheduling_cadence_settings
  where scheduling_cadence_settings.platform = p_platform
    and scheduling_cadence_settings.content_format = p_content_format
    and scheduling_cadence_settings.is_active = true
    and scheduling_cadence_settings.posts_per_week > 0;

  if not found then
    return;
  end if;

  for v_candidate in
    select
      r.platform,
      r.recommendation_rank,
      r.publish_iso_day,
      r.publish_day_name,
      r.window_start_hour,
      r.window_end_hour,
      r.time_window,
      r.post_count,
      r.recommendation_score,
      r.confidence,
      r.metrics_status,
      r.metrics_age_days
    from public.looker_joint_posting_recommendations r
    where r.platform = p_platform
      and r.post_count >= v_settings.minimum_sample_size
      and r.metrics_age_days <= v_settings.metrics_freshness_limit_days
    order by
      r.recommendation_score desc,
      r.post_count desc,
      r.publish_iso_day asc,
      r.window_start_hour asc
  loop
    exit when v_selected_count >= v_settings.posts_per_week;

    -- Use the middle of each four-hour recommendation window as the exact
    -- weekly template time: 2 AM, 6 AM, 10 AM, 2 PM, 6 PM, or 10 PM.
    v_slot_hour := least(
      v_candidate.window_start_hour + 2,
      v_candidate.window_end_hour
    );

    v_week_hour :=
      ((v_candidate.publish_iso_day - 1) * 24) + v_slot_hour;

    select count(*)
    into v_day_count
    from generate_subscripts(v_selected_days, 1) as s(i)
    where v_selected_days[s.i] = v_candidate.publish_iso_day;

    select coalesce(
      bool_and(
        least(
          abs(v_week_hour - v_selected_week_hours[s.i]),
          168 - abs(v_week_hour - v_selected_week_hours[s.i])
        ) >= v_settings.min_gap_hours
      ),
      true
    )
    into v_gap_ok
    from generate_subscripts(v_selected_week_hours, 1) as s(i);

    if v_day_count < v_settings.max_posts_per_day
       and v_gap_ok then

      v_selected_count := v_selected_count + 1;
      v_selected_days :=
        array_append(v_selected_days, v_candidate.publish_iso_day);
      v_selected_week_hours :=
        array_append(v_selected_week_hours, v_week_hour);

      platform := v_candidate.platform;
      content_format := v_settings.content_format;
      slot_rank := v_selected_count;
      source_recommendation_rank :=
        v_candidate.recommendation_rank;
      publish_iso_day := v_candidate.publish_iso_day;
      publish_day_name := v_candidate.publish_day_name;
      scheduled_hour_local := v_slot_hour;
      scheduled_time_local := make_time(v_slot_hour, 0, 0);
      recommended_window := v_candidate.time_window;
      recommendation_score := v_candidate.recommendation_score;
      confidence := v_candidate.confidence;
      supporting_sample_size := v_candidate.post_count;
      metrics_status := v_candidate.metrics_status;
      timezone_name := v_settings.timezone_name;
      slot_key :=
        v_candidate.platform
        || ':'
        || v_settings.content_format
        || ':'
        || v_candidate.publish_iso_day::text
        || ':'
        || lpad(v_slot_hour::text, 2, '0');

      return next;
    end if;
  end loop;
end;
$$;


create or replace view public.looker_scheduling_cadence_settings
with (security_invoker = false)
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
from public.scheduling_cadence_settings;


create or replace view public.looker_weekly_slot_plan
with (security_invoker = false)
as
select
  p.platform,
  p.content_format,
  p.slot_rank,
  p.source_recommendation_rank,
  p.publish_iso_day,
  p.publish_day_name,
  p.scheduled_hour_local,
  p.scheduled_time_local,
  p.recommended_window,
  p.recommendation_score,
  p.confidence,
  p.supporting_sample_size,
  p.metrics_status,
  p.timezone_name,
  p.slot_key
from public.scheduling_cadence_settings s
cross join lateral public.generate_weekly_slot_plan(
  s.platform,
  s.content_format
) p
where s.is_active = true
  and s.posts_per_week > 0;


revoke all on public.scheduling_cadence_settings
  from public, anon, authenticated;

revoke all on function public.generate_weekly_slot_plan(text, text)
  from public, anon, authenticated;

revoke all on public.looker_scheduling_cadence_settings
  from public, anon, authenticated;

revoke all on public.looker_weekly_slot_plan
  from public, anon, authenticated;

grant select on public.looker_scheduling_cadence_settings
  to creator_dashboard_reader;

grant select on public.looker_weekly_slot_plan
  to creator_dashboard_reader;

grant execute on function public.generate_weekly_slot_plan(text, text)
  to creator_dashboard_reader, service_role;

commit;
