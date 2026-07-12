-- Creator Analytics
-- Buffer post sync RPC
-- File: Database/003_sync_buffer_posts_function.sql
--
-- Accepts Buffer GraphQL "edges" as JSON and upserts each edge.node
-- into public.posts. Safe to rerun.

begin;

create or replace function public.sync_buffer_posts(
  p_posts jsonb,
  p_organization_id text
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_edge jsonb;
  v_node jsonb;
  v_count integer := 0;
begin
  if p_posts is null
     or jsonb_typeof(p_posts) <> 'array' then
    raise exception 'p_posts must be a JSON array';
  end if;

  if p_organization_id is null
     or btrim(p_organization_id) = '' then
    raise exception 'p_organization_id is required';
  end if;

  for v_edge in
    select value
    from jsonb_array_elements(p_posts)
  loop
    v_node := v_edge -> 'node';

    if v_node is null
       or coalesce(v_node ->> 'id', '') = ''
       or coalesce(v_node ->> 'channelId', '') = '' then
      continue;
    end if;

    insert into public.posts (
      buffer_post_id,
      buffer_organization_id,
      buffer_channel_id,
      channel_service,
      post_text,
      status,
      buffer_created_at,
      due_at,
      sent_at,
      external_link,
      raw_data,
      last_synced_at
    )
    values (
      v_node ->> 'id',
      p_organization_id,
      v_node ->> 'channelId',
      v_node ->> 'channelService',
      v_node ->> 'text',
      v_node ->> 'status',
      case
        when coalesce(v_node ->> 'createdAt', '') = '' then null
        else (v_node ->> 'createdAt')::timestamptz
      end,
      case
        when coalesce(v_node ->> 'dueAt', '') = '' then null
        else (v_node ->> 'dueAt')::timestamptz
      end,
      case
        when coalesce(v_node ->> 'sentAt', '') = '' then null
        else (v_node ->> 'sentAt')::timestamptz
      end,
      v_node ->> 'externalLink',
      v_node,
      now()
    )
    on conflict (buffer_post_id)
    do update set
      buffer_organization_id = excluded.buffer_organization_id,
      buffer_channel_id = excluded.buffer_channel_id,
      channel_service = excluded.channel_service,
      post_text = excluded.post_text,
      status = excluded.status,
      buffer_created_at = excluded.buffer_created_at,
      due_at = excluded.due_at,
      sent_at = excluded.sent_at,
      external_link = excluded.external_link,
      raw_data = excluded.raw_data,
      last_synced_at = now(),
      updated_at = now();

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute
  on function public.sync_buffer_posts(jsonb, text)
  from public;

revoke execute
  on function public.sync_buffer_posts(jsonb, text)
  from anon, authenticated;

grant execute
  on function public.sync_buffer_posts(jsonb, text)
  to service_role;

commit;
