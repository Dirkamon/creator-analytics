-- VERSION 2 - corrected 2026-08-03
-- No proposal_id column is referenced anywhere in this migration.
-- 028_prevent_duplicate_content_aware_proposals.sql
-- Creator Analytics
--
-- Purpose:
--   1. Backfill schedule_evaluated_at for every post that has ever had a
--      scheduling proposal.
--   2. Retire accidental Pending proposals that were created after an earlier
--      terminal proposal for the same Buffer post.
--   3. Harden both content-aware proposal creation functions so a Buffer post
--      with any proposal history cannot receive another proposal.
--   4. Preserve manual approval and prevent this migration from editing Buffer.
--
-- Root cause addressed:
--   Migration 026 created proposals without setting posts.schedule_evaluated_at.
--   After those proposals became Applied, the active-proposal check no longer
--   blocked migration 027 from proposing the same Buffer posts again.

begin;


-- ---------------------------------------------------------------------------
-- 1. Backfill the one-time scheduling evaluation lock
-- ---------------------------------------------------------------------------

update public.posts bp
set schedule_evaluated_at = history.first_proposed_at
from (
    select
        buffer_post_id,
        min(generated_at) as first_proposed_at
    from public.schedule_change_proposals
    group by buffer_post_id
) history
where bp.buffer_post_id = history.buffer_post_id
  and bp.schedule_evaluated_at is null;


-- ---------------------------------------------------------------------------
-- 2. Retire accidental duplicate Pending proposals
--
-- A Pending proposal is considered accidental when an earlier proposal for
-- the same Buffer post already reached a terminal state. We preserve the row
-- for audit history rather than deleting it.
--
-- This deliberately identifies rows by their values and timestamps because
-- schedule_change_proposals does not have a proposal_id column.
-- ---------------------------------------------------------------------------

update public.schedule_change_proposals current_proposal
set
    approval_status = 'Rejected',
    rejected_at = coalesce(current_proposal.rejected_at, now()),
    result_message = coalesce(
        current_proposal.result_message,
        'Automatically rejected by migration 028 because this Buffer post already had a completed scheduling proposal.'
    ),
    error_message = null,
    updated_at = now()
where current_proposal.approval_status = 'Pending'
  and exists (
      select 1
      from public.schedule_change_proposals prior_proposal
      where prior_proposal.buffer_post_id =
                current_proposal.buffer_post_id
        and prior_proposal.generated_at <
                current_proposal.generated_at
        and prior_proposal.approval_status in (
            'Applied',
            'Rejected',
            'Error'
        )
  );


-- ---------------------------------------------------------------------------
-- 3. Harden the manual content-aware proposal bridge from migration 026
-- ---------------------------------------------------------------------------

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
            preview.preview_key,
            preview.buffer_post_id,
            preview.platform,
            coalesce(
                preview.content_format,
                'short_form'
            ) as content_format,
            preview.post_text,
            preview.external_link,
            preview.current_due_at_utc,
            preview.current_due_at_local,
            preview.proposed_due_at_utc,
            preview.proposed_due_at_local,
            preview.slot_rank,
            preview.source_recommendation_rank,
            preview.recommendation_score,
            preview.confidence,
            preview.supporting_sample_size,
            preview.metrics_status,
            coalesce(
                preview.timezone_name,
                'America/Denver'
            ) as timezone_name,

            row_number() over (
                partition by preview.buffer_post_id
                order by
                    preview.proposed_due_at_utc asc,
                    preview.preview_key asc
            ) as buffer_post_choice

        from public.looker_content_aware_proposal_preview preview

        join public.posts post_record
          on post_record.buffer_post_id =
             preview.buffer_post_id

        where post_record.schedule_evaluated_at is null

          -- Defense in depth: the evaluation timestamp is the primary lock,
          -- while this history check protects against a missing or cleared
          -- timestamp.
          and not exists (
              select 1
              from public.schedule_change_proposals history
              where history.buffer_post_id =
                    preview.buffer_post_id
          )

          and preview.ready_to_create = true
          and preview.preview_status = 'Ready'
          and preview.has_active_proposal = false
          and preview.recommendation_ready_for_preview = true
          and preview.shadow_ready_for_live_test = true
          and preview.hybrid_guardrail_status = 'Pass'

          and preview.current_due_at_utc
              is distinct from preview.proposed_due_at_utc

          and preview.proposed_due_at_utc >
              now() + make_interval(
                  hours => coalesce(
                      preview.protected_hours,
                      24
                  )
              )
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
    ),

    inserted as (
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
            selected_post.buffer_post_id,
            selected_post.platform,
            selected_post.content_format,
            selected_post.post_text,
            selected_post.external_link,
            selected_post.current_due_at_utc,
            selected_post.current_due_at_local,
            selected_post.proposed_due_at_utc,
            selected_post.proposed_due_at_local,
            selected_post.slot_rank,
            selected_post.source_recommendation_rank,
            selected_post.recommendation_score,
            selected_post.confidence,
            selected_post.supporting_sample_size,
            selected_post.metrics_status,
            selected_post.timezone_name,
            'Pending',
            null,
            null,
            null,
            null,
            null,
            now(),
            now(),
            null
        from selected selected_post

        on conflict (buffer_post_id)
            where approval_status in ('Pending', 'Approved')
        do nothing

        returning buffer_post_id
    ),

    marked as (
        update public.posts post_record
        set schedule_evaluated_at = now()
        from inserted new_proposal
        where post_record.buffer_post_id =
              new_proposal.buffer_post_id
          and post_record.schedule_evaluated_at is null
        returning post_record.buffer_post_id
    )

    select count(*)::integer
    into v_rows_created
    from inserted;

    return v_rows_created;
end;
$function$;

revoke all on function
    public.create_content_aware_schedule_proposals(integer)
from public, anon, authenticated;

grant execute on function
    public.create_content_aware_schedule_proposals(integer)
to service_role;

comment on function
    public.create_content_aware_schedule_proposals(integer)
is
'Creates one-time Pending schedule proposals from content-aware preview rows. Requires no prior proposal history, marks inserted posts evaluated, preserves manual approval, and never edits Buffer directly.';


-- ---------------------------------------------------------------------------
-- 4. Harden the automated content-aware refresh from migration 027
-- ---------------------------------------------------------------------------

create or replace function public.refresh_schedule_proposals(
    p_start_date date default current_date,
    p_horizon_days integer default 21
)
returns integer
language plpgsql
security definer
set search_path = 'public', 'pg_temp'
as $function$
declare
    v_rows_changed integer := 0;
begin
    if p_horizon_days < 1 or p_horizon_days > 90 then
        raise exception 'p_horizon_days must be between 1 and 90';
    end if;

    if p_start_date is null then
        p_start_date := current_date;
    end if;

    with eligible as (
        select
            preview.preview_key,
            preview.buffer_post_id,
            preview.platform,
            coalesce(
                preview.content_format,
                'short_form'
            ) as content_format,
            preview.post_text,
            preview.external_link,
            preview.current_due_at_utc,
            preview.current_due_at_local,
            preview.proposed_due_at_utc,
            preview.proposed_due_at_local,
            preview.slot_rank,
            preview.source_recommendation_rank,
            preview.recommendation_score,
            preview.confidence,
            preview.supporting_sample_size,
            preview.metrics_status,
            coalesce(
                preview.timezone_name,
                'America/Denver'
            ) as timezone_name,

            row_number() over (
                partition by preview.buffer_post_id
                order by
                    preview.proposed_due_at_utc asc,
                    preview.preview_key asc
            ) as buffer_post_choice

        from public.looker_content_aware_proposal_preview preview

        join public.posts post_record
          on post_record.buffer_post_id =
             preview.buffer_post_id

        where post_record.schedule_evaluated_at is null

          -- Defense in depth against cleared/missing evaluation timestamps.
          and not exists (
              select 1
              from public.schedule_change_proposals history
              where history.buffer_post_id =
                    preview.buffer_post_id
          )

          and preview.ready_to_create = true
          and preview.preview_status = 'Ready'
          and preview.has_active_proposal = false
          and preview.recommendation_ready_for_preview = true
          and preview.shadow_ready_for_live_test = true
          and preview.hybrid_guardrail_status = 'Pass'

          and preview.current_due_at_utc
              is distinct from preview.proposed_due_at_utc

          and preview.proposed_due_at_local::date >=
              p_start_date

          and preview.proposed_due_at_local::date <=
              (p_start_date + p_horizon_days)

          and preview.proposed_due_at_utc >
              now() + make_interval(
                  hours => coalesce(
                      preview.protected_hours,
                      24
                  )
              )
    ),

    selected as (
        select *
        from eligible
        where buffer_post_choice = 1
    ),

    inserted as (
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
            selected_post.buffer_post_id,
            selected_post.platform,
            selected_post.content_format,
            selected_post.post_text,
            selected_post.external_link,
            selected_post.current_due_at_utc,
            selected_post.current_due_at_local,
            selected_post.proposed_due_at_utc,
            selected_post.proposed_due_at_local,
            selected_post.slot_rank,
            selected_post.source_recommendation_rank,
            selected_post.recommendation_score,
            selected_post.confidence,
            selected_post.supporting_sample_size,
            selected_post.metrics_status,
            selected_post.timezone_name,
            'Pending',
            null,
            null,
            null,
            null,
            null,
            now(),
            now(),
            null
        from selected selected_post

        on conflict (buffer_post_id)
            where approval_status in ('Pending', 'Approved')
        do nothing

        returning buffer_post_id
    ),

    marked as (
        update public.posts post_record
        set schedule_evaluated_at = now()
        from inserted new_proposal
        where post_record.buffer_post_id =
              new_proposal.buffer_post_id
          and post_record.schedule_evaluated_at is null
        returning post_record.buffer_post_id
    )

    select count(*)::integer
    into v_rows_changed
    from inserted;

    return v_rows_changed;
end;
$function$;

revoke all on function
    public.refresh_schedule_proposals(date, integer)
from public, anon, authenticated;

grant execute on function
    public.refresh_schedule_proposals(date, integer)
to service_role;

comment on function
    public.refresh_schedule_proposals(date, integer)
is
'Automated one-time content-aware schedule proposal refresh. Requires no prior proposal history, preserves the start-date runway, planning horizon, approval gate, evaluation lock, guardrails, and never edits Buffer directly.';


commit;
