-- Creator Analytics
-- Seed Buffer organization and connected channels
-- File: Database/002_seed_buffer_accounts.sql
-- Safe to rerun: uses PostgreSQL upserts.

begin;

insert into public.organizations (
  buffer_organization_id,
  name
)
values (
  '6871a7789e6a8cc76354ee47',
  'My Organization'
)
on conflict (buffer_organization_id)
do update set
  name = excluded.name,
  updated_at = now();

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
  is_disconnected,
  is_locked,
  is_queue_paused,
  last_synced_at
)
values
  (
    '6871a78c111211c557cbe00e',
    '6871a7789e6a8cc76354ee47',
    'youtube',
    'Jay_Good',
    'Jay_Good',
    'YouTube Channel',
    'channel',
    'America/Denver',
    'https://www.youtube.com/channel/UCcFSq_YCTcN0vsGYJLLi8CA',
    false,
    false,
    false,
    now()
  ),
  (
    '6871a7ac111211c557cd56ab',
    '6871a7789e6a8cc76354ee47',
    'tiktok',
    'jay_good303',
    'jay_good303',
    'TikTok Account',
    'account',
    'America/Denver',
    'https://www.tiktok.com/@jay_good303',
    false,
    false,
    false,
    now()
  )
on conflict (buffer_channel_id)
do update set
  buffer_organization_id = excluded.buffer_organization_id,
  service = excluded.service,
  name = excluded.name,
  display_name = excluded.display_name,
  descriptor = excluded.descriptor,
  channel_type = excluded.channel_type,
  timezone = excluded.timezone,
  external_link = excluded.external_link,
  is_disconnected = excluded.is_disconnected,
  is_locked = excluded.is_locked,
  is_queue_paused = excluded.is_queue_paused,
  last_synced_at = now(),
  updated_at = now();

commit;

-- Verification query
select
  c.service,
  c.name,
  c.timezone,
  c.is_disconnected,
  c.is_queue_paused
from public.channels c
order by c.service;
