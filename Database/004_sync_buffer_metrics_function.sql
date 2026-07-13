-- Creator Analytics
-- Buffer daily metric snapshot RPC
-- File: Database/004_sync_buffer_metrics_function.sql
--
-- Accepts Buffer GraphQL post edges containing node.metrics and stores
-- one snapshot per post per America/Denver calendar day.
-- Missing metrics remain NULL rather than being treated as zero.
-- Safe to rerun.

begin;

create or replace function public.sync_buffer_post_metrics(
  p_posts jsonb
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_edge jsonb;
  v_node jsonb;
  v_metrics jsonb;
  v_post_id text;
  v_metrics_updated_at timestamptz;
  v_captured_on date := (now() at time zone 'America/Denver')::date;
  v_count integer := 0;

  v_views bigint;
  v_reactions bigint;
  v_comments bigint;
  v_shares bigint;
  v_saves bigint;
  v_reach bigint;
  v_impressions bigint;
  v_clicks bigint;
  v_engagement_rate numeric;
  v_followers_gained bigint;
begin
  if p_posts is null
     or jsonb_typeof(p_posts) <> 'array' then
    raise exception 'p_posts must be a JSON array';
  end if;

  for v_edge in
    select value
    from jsonb_array_elements(p_posts)
  loop
    v_node := v_edge -> 'node';
    v_post_id := v_node ->> 'id';
    v_metrics := coalesce(v_node -> 'metrics', '[]'::jsonb);

    if coalesce(v_post_id, '') = ''
       or jsonb_typeof(v_metrics) <> 'array'
       or jsonb_array_length(v_metrics) = 0 then
      continue;
    end if;

    v_views := null;
    v_reactions := null;
    v_comments := null;
    v_shares := null;
    v_saves := null;
    v_reach := null;
    v_impressions := null;
    v_clicks := null;
    v_engagement_rate := null;
    v_followers_gained := null;

    select
      max(case when metric_key = 'views' then metric_value end)::bigint,
      max(case when metric_key = 'reactions' then metric_value end)::bigint,
      max(case when metric_key = 'comments' then metric_value end)::bigint,
      max(case when metric_key = 'shares' then metric_value end)::bigint,
      max(case when metric_key = 'saves' then metric_value end)::bigint,
      max(case when metric_key = 'reach' then metric_value end)::bigint,
      max(case when metric_key = 'impressions' then metric_value end)::bigint,
      max(case when metric_key in ('clicks', 'linkclicks') then metric_value end)::bigint,
      max(case when metric_key = 'engagementrate' then metric_value end),
      max(case when metric_key in ('follows', 'followersgained') then metric_value end)::bigint
    into
      v_views,
      v_reactions,
      v_comments,
      v_shares,
      v_saves,
      v_reach,
      v_impressions,
      v_clicks,
      v_engagement_rate,
      v_followers_gained
    from (
      select
        lower(regexp_replace(coalesce(m ->> 'type', ''), '[^a-zA-Z0-9]', '', 'g')) as metric_key,
        case
          when coalesce(m ->> 'value', '') ~ '^-?[0-9]+([.][0-9]+)?$'
            then (m ->> 'value')::numeric
          else null
        end as metric_value
      from jsonb_array_elements(v_metrics) as m
    ) parsed_metrics;

    v_metrics_updated_at :=
      case
        when coalesce(v_node ->> 'metricsUpdatedAt', '') = '' then null
        else (v_node ->> 'metricsUpdatedAt')::timestamptz
      end;

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
      followers_gained,
      raw_metrics
    )
    values (
      v_post_id,
      v_captured_on,
      now(),
      v_metrics_updated_at,
      v_views,
      v_reactions,
      v_comments,
      v_shares,
      v_saves,
      v_reach,
      v_impressions,
      v_clicks,
      v_engagement_rate,
      v_followers_gained,
      v_metrics
    )
    on conflict (buffer_post_id, captured_on)
    do update set
      captured_at = now(),
      metrics_updated_at = excluded.metrics_updated_at,
      views = excluded.views,
      reactions = excluded.reactions,
      comments = excluded.comments,
      shares = excluded.shares,
      saves = excluded.saves,
      reach = excluded.reach,
      impressions = excluded.impressions,
      clicks = excluded.clicks,
      engagement_rate = excluded.engagement_rate,
      followers_gained = excluded.followers_gained,
      raw_metrics = excluded.raw_metrics;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute
  on function public.sync_buffer_post_metrics(jsonb)
  from public;

revoke execute
  on function public.sync_buffer_post_metrics(jsonb)
  from anon, authenticated;

grant execute
  on function public.sync_buffer_post_metrics(jsonb)
  to service_role;

commit;
