-- Creator Analytics
-- Staging-only synthetic data for read-only web interface validation
-- File: Database/Seeds/001_staging_demo_data.sql
--
-- This script creates no external-system side effects. Every synthetic key is
-- prefixed with __STAGING_DEMO__ or uses the dedicated d3e0 UUID namespace.
-- It is safe to rerun: only those exact synthetic rows are replaced.
--
-- Safety gate: the operator must deliberately set this session value before
-- running the script:
--   set creator_analytics.seed_target = 'iepwctcayajdpvsmfmgl';

begin;

do $seed_guard$
begin
  if current_setting('creator_analytics.seed_target', true)
       is distinct from 'iepwctcayajdpvsmfmgl' then
    raise exception using
      message = 'Staging demo seed refused: target was not explicitly confirmed.',
      hint = 'Set creator_analytics.seed_target to the Creator Analytics Staging project ref for this session.';
  end if;
end
$seed_guard$;

-- Remove only an earlier copy of this synthetic fixture.
delete from public.schedule_change_proposals
where buffer_post_id like '__STAGING_DEMO__%';

delete from public.post_metric_snapshots metrics
using public.posts post
where metrics.buffer_post_id = post.buffer_post_id
  and post.buffer_post_id like '__STAGING_DEMO__%';

delete from public.posts
where buffer_post_id like '__STAGING_DEMO__%';

delete from public.content_items
where id::text like 'd3e00000-0000-4000-8000-%';

delete from public.channels
where buffer_channel_id in (
  '__STAGING_DEMO__TIKTOK',
  '__STAGING_DEMO__YOUTUBE'
);

delete from public.organizations
where buffer_organization_id = '__STAGING_DEMO__ORG';

insert into public.organizations (
  buffer_organization_id,
  name
)
values (
  '__STAGING_DEMO__ORG',
  'Creator Analytics Staging Demo'
);

insert into public.channels (
  buffer_channel_id,
  buffer_organization_id,
  service,
  name,
  display_name,
  descriptor,
  channel_type,
  timezone,
  external_link,
  last_synced_at
)
values
  (
    '__STAGING_DEMO__TIKTOK',
    '__STAGING_DEMO__ORG',
    'tiktok',
    'demo_tiktok',
    'Demo TikTok',
    'Synthetic staging channel',
    'account',
    'America/Denver',
    'https://example.invalid/creator-analytics/demo-tiktok',
    now() - interval '10 minutes'
  ),
  (
    '__STAGING_DEMO__YOUTUBE',
    '__STAGING_DEMO__ORG',
    'youtube',
    'demo_youtube',
    'Demo YouTube',
    'Synthetic staging channel',
    'channel',
    'America/Denver',
    'https://example.invalid/creator-analytics/demo-youtube',
    now() - interval '10 minutes'
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
select
  (
    'd3e00000-0000-4000-8000-'
    || lpad(item_number::text, 12, '0')
  )::uuid,
  'Demo Clip ' || lpad(item_number::text, 2, '0'),
  case
    when item_number <= 3 then 'Nebula Raiders'
    when item_number <= 6 then 'Castle Circuit'
    else 'Rift Racers'
  end,
  case
    when item_number <= 3 then 'Highlight'
    when item_number <= 6 then 'Tutorial'
    else 'Funny Moment'
  end,
  case
    when item_number <= 3 then 'Energetic'
    when item_number <= 6 then 'Focused'
    else 'Chaotic'
  end,
  case
    when item_number <= 3 then 'Cold open'
    when item_number <= 6 then 'Quick tip'
    else 'Unexpected payoff'
  end,
  24 + item_number,
  case when item_number % 2 = 0 then 'Medium' else 'High' end,
  'Synthetic recording ' || item_number,
  'Synthetic staging fixture; contains no production content.'
from generate_series(1, 9) item_number;

-- Nine historical clips, represented once on each platform. Three examples
-- land in each of three day/time windows so recommendation minimum samples
-- and the weekly slot plan can be exercised.
with fixture as (
  select
    platform.service,
    platform.channel_id,
    item_number,
    ((item_number - 1) / 3)::integer as window_number,
    ((item_number - 1) % 3 + 1)::integer as week_number
  from generate_series(1, 9) item_number
  cross join (values
    ('tiktok'::text, '__STAGING_DEMO__TIKTOK'::text),
    ('youtube'::text, '__STAGING_DEMO__YOUTUBE'::text)
  ) platform(service, channel_id)
),
timed as (
  select
    fixture.*,
    (
      date_trunc('week', timezone('America/Denver', now()))::date
      - (fixture.week_number * 7)
      + case fixture.window_number when 0 then 0 when 1 then 2 else 4 end
      + case fixture.window_number
          when 0 then time '10:15:00'
          when 1 then time '14:20:00'
          else time '18:25:00'
        end
    ) at time zone 'America/Denver' as sent_at
  from fixture
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
  external_link,
  external_post_id,
  last_synced_at,
  schedule_evaluated_at
)
select
  '__STAGING_DEMO__SENT_' || upper(service) || '_'
    || lpad(item_number::text, 2, '0'),
  '__STAGING_DEMO__ORG',
  channel_id,
  (
    'd3e00000-0000-4000-8000-'
    || lpad(item_number::text, 12, '0')
  )::uuid,
  service,
  'Synthetic ' || initcap(service) || ' performance post '
    || lpad(item_number::text, 2, '0'),
  'sent',
  sent_at - interval '5 days',
  sent_at,
  'https://example.invalid/creator-analytics/' || service || '/sent/'
    || item_number,
  'demo-' || service || '-sent-' || item_number,
  now() - interval '10 minutes',
  now() - interval '5 minutes'
from timed;

-- Two cumulative snapshots per sent post produce both current totals and a
-- meaningful daily-growth delta. Values are deterministic but synthetic.
with sent_posts as (
  select
    post.buffer_post_id,
    post.channel_service,
    substring(post.buffer_post_id from '([0-9]+)$')::integer as item_number
  from public.posts post
  where post.buffer_post_id like '__STAGING_DEMO__SENT_%'
),
snapshots as (
  select
    sent_posts.*,
    snapshot.day_offset,
    snapshot.multiplier
  from sent_posts
  cross join (values
    (1, 0.78::numeric),
    (0, 1.00::numeric)
  ) snapshot(day_offset, multiplier)
)
insert into public.post_metric_snapshots (
  buffer_post_id,
  captured_on,
  captured_at,
  metrics_updated_at,
  views,
  reactions,
  comments,
  shares,
  saves,
  reach,
  impressions,
  clicks,
  engagement_rate,
  watch_time_seconds,
  average_view_duration_seconds,
  average_percentage_viewed,
  followers_gained,
  raw_metrics
)
select
  buffer_post_id,
  current_date - day_offset,
  now() - make_interval(days => day_offset),
  now() - make_interval(days => day_offset),
  round(
    (
      case when channel_service = 'tiktok' then 1400 else 950 end
      + item_number * 175
    ) * multiplier
  )::bigint,
  round((85 + item_number * 11) * multiplier)::bigint,
  round((9 + item_number * 2) * multiplier)::bigint,
  round((5 + item_number) * multiplier)::bigint,
  round((12 + item_number * 2) * multiplier)::bigint,
  round((1100 + item_number * 140) * multiplier)::bigint,
  round((1550 + item_number * 190) * multiplier)::bigint,
  round((18 + item_number * 3) * multiplier)::bigint,
  round((0.065 + item_number * 0.002)::numeric * multiplier, 6),
  round((6400 + item_number * 540)::numeric * multiplier, 2),
  round((14 + item_number * 0.6)::numeric, 2),
  round((0.62 + item_number * 0.015)::numeric, 6),
  round((item_number / 2.0)::numeric * multiplier)::bigint,
  jsonb_build_array(
    jsonb_build_object('name', 'synthetic_fixture', 'value', true)
  )
from snapshots;

-- One unlinked sent post is pending export; a second has already been marked
-- exported. This exercises both Label Queue and System Status distinctions.
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
  external_link,
  last_synced_at,
  label_queue_exported_at
)
values
  (
    '__STAGING_DEMO__UNLABELED_PENDING',
    '__STAGING_DEMO__ORG',
    '__STAGING_DEMO__TIKTOK',
    null,
    'tiktok',
    'Synthetic unlabeled post awaiting export',
    'sent',
    now() - interval '5 days',
    now() - interval '3 days',
    'https://example.invalid/creator-analytics/unlabeled/pending',
    now() - interval '10 minutes',
    null
  ),
  (
    '__STAGING_DEMO__UNLABELED_EXPORTED',
    '__STAGING_DEMO__ORG',
    '__STAGING_DEMO__YOUTUBE',
    null,
    'youtube',
    'Synthetic unlabeled post already exported',
    'sent',
    now() - interval '7 days',
    now() - interval '4 days',
    'https://example.invalid/creator-analytics/unlabeled/exported',
    now() - interval '10 minutes',
    now() - interval '1 day'
  );

insert into public.post_metric_snapshots (
  buffer_post_id,
  captured_on,
  captured_at,
  metrics_updated_at,
  views,
  reactions,
  comments,
  shares,
  saves,
  engagement_rate,
  raw_metrics
)
select
  post_id,
  current_date,
  now(),
  now(),
  views,
  reactions,
  comments,
  shares,
  saves,
  engagement_rate,
  '[{"name":"synthetic_fixture","value":true}]'::jsonb
from (values
  ('__STAGING_DEMO__UNLABELED_PENDING'::text, 780::bigint, 66::bigint,
   8::bigint, 4::bigint, 9::bigint, 0.071::numeric),
  ('__STAGING_DEMO__UNLABELED_EXPORTED'::text, 640::bigint, 48::bigint,
   5::bigint, 3::bigint, 7::bigint, 0.058::numeric)
) metric(post_id, views, reactions, comments, shares, saves, engagement_rate);

-- Four future synchronized posts exercise Upcoming Posts. Their current
-- times are deliberately distinct from the proposal targets below.
with fixture as (
  select *
  from (values
    (1, 'tiktok'::text, '__STAGING_DEMO__TIKTOK'::text, 2, time '10:00:00'),
    (2, 'youtube'::text, '__STAGING_DEMO__YOUTUBE'::text, 3, time '15:00:00'),
    (3, 'tiktok'::text, '__STAGING_DEMO__TIKTOK'::text, 4, time '20:00:00'),
    (4, 'youtube'::text, '__STAGING_DEMO__YOUTUBE'::text, 5, time '11:00:00'),
    (5, 'tiktok'::text, '__STAGING_DEMO__TIKTOK'::text, 6, time '17:00:00')
  ) value(post_number, service, channel_id, day_offset, local_time)
),
timed as (
  select
    fixture.*,
    (
      timezone('America/Denver', now())::date
      + day_offset
      + local_time
    ) at time zone 'America/Denver' as due_at
  from fixture
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
  due_at,
  external_link,
  last_synced_at,
  schedule_evaluated_at
)
select
  '__STAGING_DEMO__SCHEDULED_' || post_number,
  '__STAGING_DEMO__ORG',
  channel_id,
  case
    when post_number = 4 then null
    else (
      'd3e00000-0000-4000-8000-'
      || lpad(post_number::text, 12, '0')
    )::uuid
  end,
  service,
  'Synthetic upcoming post ' || post_number,
  'scheduled',
  now() - interval '2 days',
  due_at,
  'https://example.invalid/creator-analytics/upcoming/' || post_number,
  now() - interval '10 minutes',
  case when post_number = 5 then null else now() - interval '5 minutes' end
from timed;

-- Pending, Approved, and Error examples are observation-only. They never call
-- Buffer and the Phase 1 web application has no mutation controls.
with proposal_fixture as (
  select *
  from (values
    (
      'd3e01000-0000-4000-8000-000000000001'::uuid,
      '__STAGING_DEMO__SCHEDULED_1'::text,
      'tiktok'::text,
      8,
      time '14:00:00',
      'Pending'::text,
      null::text
    ),
    (
      'd3e01000-0000-4000-8000-000000000002'::uuid,
      '__STAGING_DEMO__SCHEDULED_2'::text,
      'youtube'::text,
      9,
      time '18:00:00',
      'Approved'::text,
      null::text
    ),
    (
      'd3e01000-0000-4000-8000-000000000003'::uuid,
      '__STAGING_DEMO__SCHEDULED_3'::text,
      'tiktok'::text,
      10,
      time '20:00:00',
      'Error'::text,
      'Synthetic validation example; no external request was made.'::text
    )
  ) value(
    proposal_id,
    buffer_post_id,
    platform,
    day_offset,
    local_time,
    approval_status,
    error_message
  )
),
prepared as (
  select
    fixture.*,
    post.post_text,
    post.external_link,
    post.due_at as current_due_at_utc,
    post.due_at at time zone 'America/Denver' as current_due_at_local,
    (
      timezone('America/Denver', now())::date
      + fixture.day_offset
      + fixture.local_time
    ) at time zone 'America/Denver' as proposed_due_at_utc,
    timezone('America/Denver', now())::date
      + fixture.day_offset
      + fixture.local_time as proposed_due_at_local
  from proposal_fixture fixture
  join public.posts post using (buffer_post_id)
)
insert into public.schedule_change_proposals (
  id,
  buffer_post_id,
  platform,
  content_format,
  post_text,
  external_link,
  current_due_at_utc,
  current_due_at_local,
  proposed_due_at_utc,
  proposed_due_at_local,
  slot_rank,
  source_recommendation_rank,
  recommendation_score,
  confidence,
  supporting_sample_size,
  metrics_status,
  timezone_name,
  approval_status,
  approved_at,
  error_message,
  generated_at,
  updated_at,
  sheet_exported_at
)
select
  proposal_id,
  buffer_post_id,
  platform,
  'short_form',
  post_text,
  external_link,
  current_due_at_utc,
  current_due_at_local,
  proposed_due_at_utc,
  proposed_due_at_local,
  1,
  1,
  0.82,
  'Medium',
  9,
  'Fresh',
  'America/Denver',
  approval_status,
  case when approval_status = 'Approved' then now() else null end,
  error_message,
  now(),
  now(),
  case when approval_status = 'Pending' then null else now() end
from prepared;

commit;

-- Sanitized verification summary. Expected values after a successful run:
-- 25 posts, 20 sent, 5 scheduled, 3 proposals, 3 unlinked posts.
select
  count(*)::integer as demo_posts,
  count(*) filter (where status = 'sent')::integer as sent_posts,
  count(*) filter (where status = 'scheduled')::integer as scheduled_posts,
  count(*) filter (where content_item_id is null)::integer as unlinked_posts
from public.posts
where buffer_post_id like '__STAGING_DEMO__%';

select
  count(*)::integer as demo_metric_snapshots
from public.post_metric_snapshots metrics
where metrics.buffer_post_id like '__STAGING_DEMO__%';

select
  count(*)::integer as demo_proposals
from public.schedule_change_proposals proposal
where proposal.buffer_post_id like '__STAGING_DEMO__%';
