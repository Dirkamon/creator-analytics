-- 026_create_content_aware_schedule_proposals.sql
-- Creates a controlled, manual bridge from the content-aware proposal preview
-- into the existing schedule_change_proposals approval workflow.
--
-- This migration does NOT run the bridge automatically and does NOT move
-- anything in Buffer. It only creates the RPC/function.

begin;

create or replace function public.create_content_aware_schedule_proposals(
    p_limit integer default 50
)
returns integer
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
    v_rows_created integer := 0;
begin
    if p_limit < 1 or p_limit > 500 then
        raise exception 'p_limit must be between 1 and 500';
    end if;

    with eligible as (
        select
            p.preview_key,
            p.buffer_post_id,
            p.platform,
            coalesce(p.content_format, 'short_form') as content_format,
            p.post_text,
            p.external_link,
            p.current_due_at_utc,
            p.current_due_at_local,
            p.proposed_due_at_utc,
            p.proposed_due_at_local,
            p.slot_rank,
            p.source_recommendation_rank,
            p.recommendation_score,
            p.confidence,
            p.supporting_sample_size,
            p.metrics_status,
            coalesce(p.timezone_name, 'America/Denver') as timezone_name,
            row_number() over (
                partition by p.buffer_post_id
                order by
                    p.proposed_due_at_utc asc,
                    p.preview_key asc
            ) as buffer_post_choice
        from public.looker_content_aware_proposal_preview p
        where p.ready_to_create = true
          and p.preview_status = 'Ready'
          and p.has_active_proposal = false
          and p.recommendation_ready_for_preview = true
          and p.shadow_ready_for_live_test = true
          and p.hybrid_guardrail_status = 'Pass'
          and p.current_due_at_utc is distinct from p.proposed_due_at_utc
          and p.proposed_due_at_utc >
              now() + make_interval(hours => coalesce(p.protected_hours, 24))
    ),
    selected as (
        select *
        from eligible
        where buffer_post_choice = 1
        order by
            platform asc,
            proposed_due_at_utc asc,
            buffer_post_id asc
        limit p_limit
    )
    insert into public.schedule_change_proposals (
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
        rejected_at,
        applied_at,
        result_message,
        error_message,
        generated_at,
        updated_at,
        sheet_exported_at
    )
    select
        s.buffer_post_id,
        s.platform,
        s.content_format,
        s.post_text,
        s.external_link,
        s.current_due_at_utc,
        s.current_due_at_local,
        s.proposed_due_at_utc,
        s.proposed_due_at_local,
        s.slot_rank,
        s.source_recommendation_rank,
        s.recommendation_score,
        s.confidence,
        s.supporting_sample_size,
        s.metrics_status,
        s.timezone_name,
        'Pending',
        null,
        null,
        null,
        null,
        null,
        now(),
        now(),
        null
    from selected s
    on conflict (buffer_post_id)
        where approval_status in ('Pending', 'Approved')
    do nothing;

    get diagnostics v_rows_created = row_count;

    return v_rows_created;
end;
$function$;

revoke all on function public.create_content_aware_schedule_proposals(integer)
    from public, anon, authenticated;

grant execute on function public.create_content_aware_schedule_proposals(integer)
    to service_role;

comment on function public.create_content_aware_schedule_proposals(integer) is
'Creates Pending schedule proposals from rows that pass the content-aware hybrid preview and guardrails. Manual invocation only; does not edit Buffer directly.';

commit;
