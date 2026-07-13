-- Creator Analytics
-- Process one labeled Google Sheets row via JSON payload
-- File: Database/009_process_content_label_payload.sql
--
-- Uses a single JSONB argument so optional fields may be omitted safely.
-- Safe to rerun.

begin;

create or replace function public.process_content_label_payload(
  p_payload jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_post_id text;
  v_clip_group text;
  v_game text;
  v_content_type text;
  v_vibe text;
  v_hook_type text;
  v_duration_seconds numeric;
  v_editing_intensity text;
  v_source_recording text;
  v_notes text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'p_payload must be a JSON object';
  end if;

  v_post_id := p_payload ->> 'post_id';
  v_clip_group := p_payload ->> 'clip_group';
  v_game := p_payload ->> 'game';
  v_content_type := p_payload ->> 'content_type';
  v_vibe := p_payload ->> 'vibe';
  v_hook_type := p_payload ->> 'hook_type';
  v_editing_intensity := p_payload ->> 'editing_intensity';
  v_source_recording := p_payload ->> 'source_recording';
  v_notes := p_payload ->> 'notes';

  if coalesce(p_payload ->> 'duration_seconds', '') ~ '^[0-9]+([.][0-9]+)?$' then
    v_duration_seconds := (p_payload ->> 'duration_seconds')::numeric;
  else
    v_duration_seconds := null;
  end if;

  return public.process_content_label_row(
    p_post_id := v_post_id,
    p_clip_group := v_clip_group,
    p_game := v_game,
    p_content_type := v_content_type,
    p_vibe := v_vibe,
    p_hook_type := v_hook_type,
    p_duration_seconds := v_duration_seconds,
    p_editing_intensity := v_editing_intensity,
    p_source_recording := v_source_recording,
    p_notes := v_notes
  );
end;
$$;

revoke execute
  on function public.process_content_label_payload(jsonb)
  from public;

revoke execute
  on function public.process_content_label_payload(jsonb)
  from anon, authenticated;

grant execute
  on function public.process_content_label_payload(jsonb)
  to service_role;

notify pgrst, 'reload schema';

commit;
