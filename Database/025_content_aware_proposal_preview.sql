-- 025_content_aware_proposal_preview.sql
-- Preview-only bridge between the hybrid content-aware shadow schedule
-- and the existing schedule_change_proposals workflow.
--
-- This migration does NOT insert, update, approve, or apply any proposals.

begin;

drop view if exists public.looker_content_aware_proposal_preview_summary;
drop view if exists public.looker_content_aware_proposal_preview;

create view public.looker_content_aware_proposal_preview as
with active_proposals as (
    select distinct on (p.buffer_post_id)
        p.buffer_post_id,
        p.id as active_proposal_id,
        p.approval_status as active_proposal_status,
        p.proposed_due_at_utc as active_proposed_due_at_utc,
        p.proposed_due_at_local as active_proposed_due_at_local,
        p.generated_at as active_proposal_generated_at,
        p.updated_at as active_proposal_updated_at
    from public.schedule_change_proposals p
    where p.approval_status in ('Pending', 'Approved')
    order by
        p.buffer_post_id,
        p.updated_at desc,
        p.generated_at desc,
        p.id desc
),
preview_base as (
    select
        h.*,
        ap.active_proposal_id,
        ap.active_proposal_status,
        ap.active_proposed_due_at_utc,
        ap.active_proposed_due_at_local,
        ap.active_proposal_generated_at,
        ap.active_proposal_updated_at,

        case
            when h.selected_model_level = 'Platform Overall'
                then coalesce(
                    h.platform_slot_recommendation_score,
                    h.platform_plan_score
                )
            else coalesce(
                h.content_recommendation_score,
                h.platform_slot_recommendation_score,
                h.platform_plan_score
            )
        end as proposal_recommendation_score,

        case
            when h.selected_model_level = 'Platform Overall'
                then coalesce(
                    h.platform_slot_confidence,
                    h.platform_plan_confidence
                )
            else coalesce(
                h.content_confidence,
                h.platform_slot_confidence,
                h.platform_plan_confidence
            )
        end as proposal_confidence,

        case
            when h.selected_model_level = 'Platform Overall'
                then coalesce(
                    h.platform_slot_supporting_sample_size,
                    h.platform_plan_supporting_sample_size,
                    0
                )
            else coalesce(
                h.group_sample_size,
                h.platform_slot_supporting_sample_size,
                h.platform_plan_supporting_sample_size,
                0
            )
        end as proposal_supporting_sample_size,

        case
            when h.selected_model_level = 'Platform Overall'
                then coalesce(
                    h.platform_slot_metrics_status,
                    h.platform_plan_metrics_status
                )
            else coalesce(
                h.content_metrics_status,
                h.platform_slot_metrics_status,
                h.platform_plan_metrics_status
            )
        end as proposal_metrics_status

    from public.looker_content_aware_hybrid_shadow_schedule h
    left join active_proposals ap
        on ap.buffer_post_id = h.buffer_post_id

    -- Preview only actual schedule changes.
    where h.current_buffer_due_at_utc
        is distinct from h.hybrid_proposed_at_utc
),
preview_ready as (
    select
        pb.*,

        (
            coalesce(pb.shadow_ready_for_live_test, false)
            and coalesce(pb.recommendation_ready_for_preview, false)
            and pb.hybrid_guardrail_status = 'Pass'
            and coalesce(pb.stayed_inside_cadence_cycle, false)
            and pb.active_proposal_id is null
        ) as ready_to_create,

        case
            when pb.active_proposal_id is not null then
                'Blocked: active '
                || pb.active_proposal_status
                || ' proposal already exists'
            when not coalesce(pb.shadow_ready_for_live_test, false) then
                'Blocked: hybrid shadow row is not ready for live testing'
            when not coalesce(pb.recommendation_ready_for_preview, false) then
                'Blocked: recommendation is not ready for preview'
            when pb.hybrid_guardrail_status is distinct from 'Pass' then
                'Blocked: hybrid guardrail status is '
                || coalesce(pb.hybrid_guardrail_status, '(missing)')
            when not coalesce(pb.stayed_inside_cadence_cycle, false) then
                'Blocked: proposed time left the assigned cadence cycle'
            else
                null
        end as blocking_reason

    from preview_base pb
)
select
    -- Stable preview identifier. This is not the proposal table UUID.
    md5(
        concat_ws(
            '|',
            pr.buffer_post_id,
            pr.hybrid_proposed_at_utc::text,
            pr.selected_model_level,
            pr.content_match_class
        )
    ) as preview_key,

    -- Exact schedule_change_proposals-shaped fields.
    pr.buffer_post_id,
    pr.platform,
    pr.content_format,
    pr.post_text,
    pr.external_link,
    pr.current_buffer_due_at_utc as current_due_at_utc,
    pr.current_buffer_due_at_local as current_due_at_local,
    pr.hybrid_proposed_at_utc as proposed_due_at_utc,
    pr.hybrid_proposed_at_local as proposed_due_at_local,
    pr.hybrid_slot_rank as slot_rank,
    pr.hybrid_source_recommendation_rank as source_recommendation_rank,
    pr.proposal_recommendation_score as recommendation_score,
    pr.proposal_confidence as confidence,
    pr.proposal_supporting_sample_size as supporting_sample_size,
    pr.proposal_metrics_status as metrics_status,
    pr.timezone_name,
    'Pending'::text as approval_status,
    null::timestamptz as approved_at,
    null::timestamptz as rejected_at,
    null::timestamptz as applied_at,
    null::text as result_message,
    null::text as error_message,
    now() as generated_at,
    now() as updated_at,
    null::timestamptz as sheet_exported_at,

    -- Preview and safety fields.
    pr.ready_to_create,
    case
        when pr.ready_to_create then 'Ready'
        else 'Blocked'
    end as preview_status,
    pr.blocking_reason,
    (pr.active_proposal_id is not null) as has_active_proposal,
    pr.active_proposal_id,
    pr.active_proposal_status,
    pr.active_proposed_due_at_utc,
    pr.active_proposed_due_at_local,
    pr.active_proposal_generated_at,
    pr.active_proposal_updated_at,

    -- Content labels and model-selection details.
    pr.clip_group,
    pr.game,
    pr.content_type,
    pr.vibe,
    pr.hook_type,
    pr.labels_complete,
    pr.selected_model_level,
    pr.selected_model_priority,
    pr.selected_content_group,
    pr.group_sample_size,
    pr.minimum_sample_size,
    pr.fallback_reason,

    -- Platform plan and content-aware comparison.
    pr.platform_plan_proposed_at_utc,
    pr.platform_plan_proposed_at_local,
    pr.platform_plan_window,
    pr.platform_plan_score,
    pr.platform_plan_confidence,
    pr.content_recommended_slot,
    pr.content_recommendation_score,
    pr.content_confidence,
    pr.content_metrics_status,
    pr.content_match_class,
    pr.content_day_matches,
    pr.content_window_matches,
    pr.content_day_distance,
    pr.content_hour_distance,
    pr.hybrid_assignment_score,
    pr.platform_plan_comparison,
    pr.exact_platform_plan_match,
    pr.platform_plan_shift_hours,

    -- Final hybrid schedule and guardrails.
    pr.post_sequence,
    pr.cadence_cycle,
    pr.assignment_sequence,
    pr.hybrid_slot_sequence,
    pr.hybrid_cycle_slot_position,
    pr.hybrid_publish_iso_day,
    pr.hybrid_publish_day_name,
    pr.hybrid_hour_local,
    pr.hybrid_time_local,
    pr.hybrid_recommended_window,
    pr.hybrid_posts_that_day,
    pr.hybrid_gap_hours,
    pr.hybrid_guardrail_status,
    pr.stayed_inside_cadence_cycle,
    pr.shadow_ready_for_live_test,
    pr.recommendation_ready_for_preview,
    pr.max_posts_per_day,
    pr.min_gap_hours,
    pr.protected_hours

from preview_ready pr;

comment on view public.looker_content_aware_proposal_preview is
'Preview-only mapping of the content-aware hybrid shadow schedule into the schedule_change_proposals shape. Excludes no-op changes and flags active Pending/Approved proposals.';

create view public.looker_content_aware_proposal_preview_summary as
select
    platform,
    count(*)::integer as preview_rows,
    count(*) filter (where ready_to_create)::integer as ready_to_create,
    count(*) filter (where not ready_to_create)::integer as blocked_rows,
    count(*) filter (where has_active_proposal)::integer
        as blocked_by_active_proposal,
    count(*) filter (
        where selected_model_level <> 'Platform Overall'
    )::integer as content_specific_rows,
    count(*) filter (
        where selected_model_level = 'Platform Overall'
    )::integer as platform_overall_fallback_rows,
    count(*) filter (
        where content_day_matches and content_window_matches
    )::integer as exact_content_day_and_window_rows,
    count(*) filter (
        where exact_platform_plan_match
    )::integer as unchanged_from_platform_plan_rows,
    count(*) filter (
        where not exact_platform_plan_match
    )::integer as reassigned_inside_cadence_cycle_rows,
    count(*) filter (
        where hybrid_guardrail_status = 'Pass'
    )::integer as guardrail_pass_rows,
    min(proposed_due_at_local) as first_proposed_at_local,
    max(proposed_due_at_local) as last_proposed_at_local
from public.looker_content_aware_proposal_preview
group by platform;

comment on view public.looker_content_aware_proposal_preview_summary is
'Platform-level summary of the content-aware proposal preview, including readiness, active-proposal blocks, content specificity, and guardrail results.';

grant select on public.looker_content_aware_proposal_preview
    to service_role;

grant select on public.looker_content_aware_proposal_preview_summary
    to service_role;

do $$
begin
    if exists (
        select 1
        from pg_roles
        where rolname = 'creator_dashboard_reader'
    ) then
        grant select on public.looker_content_aware_proposal_preview
            to creator_dashboard_reader;

        grant select on public.looker_content_aware_proposal_preview_summary
            to creator_dashboard_reader;
    end if;
end;
$$;

commit;
