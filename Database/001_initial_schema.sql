-- Creator Analytics
-- Initial Supabase database schema
-- File: Database/001_initial_schema.sql

begin;

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.organizations (
  buffer_organization_id text primary key,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.channels (
  buffer_channel_id text primary key,
  buffer_organization_id text not null
    references public.organizations(buffer_organization_id)
    on delete cascade,
  service text not null,
  name text,
  display_name text,
  descriptor text,
  channel_type text,
  timezone text,
  external_link text,
  is_disconnected boolean not null default false,
  is_locked boolean not null default false,
  is_queue_paused boolean not null default false,
  raw_data jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.content_items (
  id uuid primary key default gen_random_uuid(),
  internal_title text,
  game text,
  content_type text,
  vibe text,
  hook_type text,
  duration_seconds numeric(10, 2)
    check (duration_seconds is null or duration_seconds >= 0),
  editing_intensity text,
  source_recording text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  buffer_post_id text primary key,
  buffer_organization_id text not null
    references public.organizations(buffer_organization_id)
    on delete cascade,
  buffer_channel_id text not null
    references public.channels(buffer_channel_id)
    on delete cascade,
  content_item_id uuid
    references public.content_items(id)
    on delete set null,
  channel_service text,
  post_text text,
  status text,
  buffer_created_at timestamptz,
  due_at timestamptz,
  sent_at timestamptz,
  external_link text,
  external_post_id text,
  raw_data jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_synced_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.post_metric_snapshots (
  id bigint generated always as identity primary key,
  buffer_post_id text not null
    references public.posts(buffer_post_id)
    on delete cascade,
  captured_on date not null
    default ((now() at time zone 'America/Denver')::date),
  captured_at timestamptz not null default now(),
  metrics_updated_at timestamptz,
  views bigint,
  reactions bigint,
  comments bigint,
  shares bigint,
  saves bigint,
  reach bigint,
  impressions bigint,
  clicks bigint,
  engagement_rate numeric(12, 6),
  watch_time_seconds numeric(18, 2),
  average_view_duration_seconds numeric(18, 2),
  average_percentage_viewed numeric(12, 6),
  followers_gained bigint,
  raw_metrics jsonb not null default '[]'::jsonb,
  unique (buffer_post_id, captured_on)
);

create table if not exists public.schedule_recommendations (
  id uuid primary key default gen_random_uuid(),
  buffer_channel_id text not null
    references public.channels(buffer_channel_id)
    on delete cascade,
  game text,
  content_type text,
  recommended_day_of_week smallint
    check (
      recommended_day_of_week is null
      or recommended_day_of_week between 0 and 6
    ),
  recommended_local_time time,
  confidence numeric(6, 5)
    check (confidence is null or confidence between 0 and 1),
  sample_size integer
    check (sample_size is null or sample_size >= 0),
  expected_lift_percent numeric(12, 4),
  rationale text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'applied', 'expired')),
  valid_from date,
  valid_until date,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.automation_runs (
  id bigint generated always as identity primary key,
  automation_name text not null,
  status text not null
    check (status in ('running', 'success', 'partial', 'failed')),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  records_processed integer not null default 0,
  error_message text,
  details jsonb not null default '{}'::jsonb
);

create index if not exists channels_organization_idx
  on public.channels (buffer_organization_id);

create index if not exists posts_channel_status_idx
  on public.posts (buffer_channel_id, status);

create index if not exists posts_sent_at_idx
  on public.posts (sent_at desc);

create index if not exists posts_due_at_idx
  on public.posts (due_at asc);

create index if not exists posts_content_item_idx
  on public.posts (content_item_id);

create index if not exists metric_snapshots_post_date_idx
  on public.post_metric_snapshots (buffer_post_id, captured_on desc);

create index if not exists recommendations_channel_status_idx
  on public.schedule_recommendations (buffer_channel_id, status);

create index if not exists automation_runs_name_started_idx
  on public.automation_runs (automation_name, started_at desc);

drop trigger if exists organizations_set_updated_at on public.organizations;
create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();

drop trigger if exists channels_set_updated_at on public.channels;
create trigger channels_set_updated_at
before update on public.channels
for each row execute function public.set_updated_at();

drop trigger if exists content_items_set_updated_at on public.content_items;
create trigger content_items_set_updated_at
before update on public.content_items
for each row execute function public.set_updated_at();

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at
before update on public.posts
for each row execute function public.set_updated_at();

drop trigger if exists schedule_recommendations_set_updated_at
  on public.schedule_recommendations;
create trigger schedule_recommendations_set_updated_at
before update on public.schedule_recommendations
for each row execute function public.set_updated_at();

alter table public.organizations enable row level security;
alter table public.channels enable row level security;
alter table public.content_items enable row level security;
alter table public.posts enable row level security;
alter table public.post_metric_snapshots enable row level security;
alter table public.schedule_recommendations enable row level security;
alter table public.automation_runs enable row level security;

commit;
