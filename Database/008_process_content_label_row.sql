-- Creator Analytics
-- Process one labeled Google Sheets row
-- File: Database/008_process_content_label_row.sql
--
-- Uses Clip Group as a stable key. Rows with the same Clip Group
-- (for example, TikTok and YouTube versions of the same clip)
-- are linked to the same content_items record.
-- Safe to rerun.

begin;

create unique index if not exists content_items_internal_title_unique_idx
  on public.content_items (internal_title)
  where internal_title is not null;

create or replace function public.process_content_label_row(
  p_post_id text,
  p_clip_group text,
  p_game text,
  p_content_type text,
  p_vibe text,
  p_hook_type text default null,
  p_duration_seconds numeric default null,
  p_editing_intensity text default null,
  p_source_recording text default null,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_content_item_id uuid;
  v_existing_content_item_id uuid;
  v_clip_group text;
begin
  v_clip_group := lower(nullif(btrim(p_clip_group), ''));

  if coalesce(btrim(p_post_id), '') = '' then
    raise exception 'Buffer post ID is required';
  end if;

  if v_clip_group is null then
    raise exception 'Clip Group is required';
  end if;

  if coalesce(btrim(p_game), '') = '' then
    raise exception 'Game is required';
  end if;

  if coalesce(btrim(p_content_type), '') = '' then
    raise exception 'Content Type is required';
  end if;

  if coalesce(btrim(p_vibe), '') = '' then
    raise exception 'Vibe is required';
  end if;

  select content_item_id
  into v_existing_content_item_id
  from public.posts
  where buffer_post_id = p_post_id;

  if not found then
    raise exception 'Buffer post ID % does not exist', p_post_id;
  end if;

  if v_existing_content_item_id is not null then
    return v_existing_content_item_id;
  end if;

  insert into public.content_items (
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
  values (
    v_clip_group,
    btrim(p_game),
    btrim(p_content_type),
    btrim(p_vibe),
    nullif(btrim(p_hook_type), ''),
    p_duration_seconds,
    nullif(btrim(p_editing_intensity), ''),
    nullif(btrim(p_source_recording), ''),
    nullif(btrim(p_notes), '')
  )
  on conflict (internal_title)
  where internal_title is not null
  do update set
    game = excluded.game,
    content_type = excluded.content_type,
    vibe = excluded.vibe,
    hook_type = coalesce(excluded.hook_type, public.content_items.hook_type),
    duration_seconds = coalesce(
      excluded.duration_seconds,
      public.content_items.duration_seconds
    ),
    editing_intensity = coalesce(
      excluded.editing_intensity,
      public.content_items.editing_intensity
    ),
    source_recording = coalesce(
      excluded.source_recording,
      public.content_items.source_recording
    ),
    notes = coalesce(excluded.notes, public.content_items.notes),
    updated_at = now()
  returning id into v_content_item_id;

  update public.posts
  set
    content_item_id = v_content_item_id,
    updated_at = now()
  where buffer_post_id = p_post_id;

  return v_content_item_id;
end;
$$;

revoke execute
  on function public.process_content_label_row(
    text, text, text, text, text, text, numeric, text, text, text
  )
  from public;

revoke execute
  on function public.process_content_label_row(
    text, text, text, text, text, text, numeric, text, text, text
  )
  from anon, authenticated;

grant execute
  on function public.process_content_label_row(
    text, text, text, text, text, text, numeric, text, text, text
  )
  to service_role;

commit;
