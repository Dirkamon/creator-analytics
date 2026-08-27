-- Creator Analytics
-- Regression coverage for migration 032
-- File: Tests/Database/032_optimize_range_aware_schedule_proposal_generation_regression.sql
--
-- First execute the complete migration-031 regression unchanged. It covers the
-- historical collision, the eight-post real generator, all 256 approval
-- subsets, capacity/gap boundaries, self-exclusion, Applied reservations,
-- history/evaluation protection, permissions, contracts, and concurrency-safe
-- function structure. That included script ends in ROLLBACK.

\ir 031_optimize_schedule_proposal_generation_regression.sql

begin;

set local timezone = 'UTC';
set local statement_timeout = '2min';
set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 1. Exact migration-032 scope, ownership, security, and contract guards
-- ---------------------------------------------------------------------------

do $test$
declare
  v_definition text;
  v_acl text[];
  v_all_view_contract_hash text;
  v_view_count integer;
  v_make_contract text[];
begin
  select lower(pg_catalog.pg_get_functiondef(function_record.oid))
  into v_definition
  from pg_catalog.pg_proc function_record
  where function_record.oid =
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure;

  if position('pg_advisory_xact_lock' in v_definition) = 0
     or position('for update of post_record' in v_definition) = 0
     or position('requested_cycle_bounds as materialized' in v_definition) = 0
     or position('reservation_inventory as materialized' in v_definition) = 0
     or position('candidate_reservation_state as materialized' in v_definition) = 0
     or position('candidate_option_arrays as materialized' in v_definition) = 0
     or position('schedule_evaluated_at is null' in v_definition) = 0
     or position('schedule_change_proposals history' in v_definition) = 0
     or position('last_synced_at' in lower(pg_catalog.pg_get_viewdef(
          'public.schedule_slot_reservations'::regclass,
          true
        ))) = 0 then
    raise exception
      'Migration 032 generator lost a required range, lock, reservation, or history safeguard';
  end if;

  if regexp_count(v_definition, 'schedule_slot_reservations') <> 1
     or position('looker_content_aware_proposal_preview' in v_definition) > 0
     or position('looker_content_aware_hybrid_shadow_schedule' in v_definition) > 0
     or position('find_schedule_slot_conflicts' in v_definition) > 0
     or position('get_schedule_reservation_capacity' in v_definition) > 0
     or position('calculate_schedule_reservation_state' in v_definition) > 0 then
    raise exception
      'Migration 032 did not remove repeated reservation/reporting-preview work';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc function_record
    where function_record.oid =
      'public.create_collision_safe_schedule_proposals(integer,date,date)'
        ::regprocedure
      and pg_catalog.pg_get_userbyid(function_record.proowner) = current_user
      and function_record.prosecdef
      and function_record.provolatile = 'v'
      and function_record.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception
      'Migration 032 generator owner/security/volatility/search_path changed';
  end if;

  select array_agg(
    format(
      '%s:%s',
      coalesce(grantee.rolname, 'PUBLIC'),
      acl.privilege_type
    ) order by coalesce(grantee.rolname, 'PUBLIC'), acl.privilege_type
  )
  into v_acl
  from pg_catalog.pg_proc function_record
  cross join lateral aclexplode(
    coalesce(
      function_record.proacl,
      acldefault('f', function_record.proowner)
    )
  ) acl
  left join pg_catalog.pg_roles grantee
    on grantee.oid = acl.grantee
  where function_record.oid =
    'public.create_collision_safe_schedule_proposals(integer,date,date)'
      ::regprocedure
    and acl.grantee <> function_record.proowner;

  if v_acl is not null then
    raise exception
      'Internal migration-032 generator unexpectedly grants non-owner EXECUTE: %',
      v_acl;
  end if;

  if encode(
       digest(
         pg_catalog.pg_get_functiondef(
           'public.create_content_aware_schedule_proposals(integer)'
             ::regprocedure
         ),
         'sha256'
       ),
       'hex'
     ) <> '928d6ac8c5722dda671a219a8ff7cc651d01221ea4c2d8f764088f74d98acd4f'
     or encode(
       digest(
         pg_catalog.pg_get_functiondef(
           'public.refresh_schedule_proposals(date,integer)'::regprocedure
         ),
         'sha256'
       ),
       'hex'
     ) <> 'b3e4cc0242af35979122a66d0e9d3c4e899350c6b4f7912a7576cb4d0007b9b2' then
    raise exception 'Migration 032 changed a public wrapper definition';
  end if;

  with view_contracts as (
    select
      relation.relname,
      count(attribute.*)::integer as column_count,
      encode(
        digest(
          string_agg(
            format(
              '%s:%s',
              attribute.attname,
              pg_catalog.format_type(
                attribute.atttypid,
                attribute.atttypmod
              )
            ),
            E'\n'
            order by attribute.attnum
          ),
          'sha256'
        ),
        'hex'
      ) as contract_hash
    from pg_catalog.pg_class relation
    join pg_catalog.pg_namespace namespace
      on namespace.oid = relation.relnamespace
    join pg_catalog.pg_attribute attribute
      on attribute.attrelid = relation.oid
     and attribute.attnum > 0
     and not attribute.attisdropped
    where namespace.nspname = 'public'
      and relation.relkind = 'v'
    group by relation.relname
  )
  select
    encode(
      digest(
        string_agg(
          format('%s:%s:%s', relname, column_count, contract_hash),
          E'\n'
          order by relname
        ),
        'sha256'
      ),
      'hex'
    ),
    count(*)::integer
  into v_all_view_contract_hash, v_view_count
  from view_contracts;

  if v_view_count <> 31
     or v_all_view_contract_hash <>
       '2e2cf708ad8656f843b198a2e695ac33c8f0f75d405576352e6ff39c2ee4fbd7' then
    raise exception
      'Migration 032 changed a reporting/service view column contract: count %, hash %',
      v_view_count,
      v_all_view_contract_hash;
  end if;

  select array_agg(
    format('%s:%s:%s', column_name, data_type, udt_name)
    order by ordinal_position
  )
  into v_make_contract
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'approved_schedule_changes_ready_to_apply';

  if v_make_contract is distinct from array[
    'proposal_id:uuid:uuid',
    'buffer_post_id:text:text',
    'platform:text:text',
    'content_format:text:text',
    'post_text:text:text',
    'external_link:text:text',
    'current_due_at_utc:timestamp with time zone:timestamptz',
    'current_due_at_local:timestamp without time zone:timestamp',
    'proposed_due_at_utc:timestamp with time zone:timestamptz',
    'proposed_due_at_local:timestamp without time zone:timestamp',
    'slot_rank:integer:int4',
    'source_recommendation_rank:integer:int4',
    'recommendation_score:numeric:numeric',
    'confidence:text:text',
    'supporting_sample_size:integer:int4',
    'metrics_status:text:text',
    'timezone_name:text:text',
    'approval_status:text:text',
    'approved_at:timestamp with time zone:timestamptz'
  ]::text[] then
    raise exception 'Migration 032 changed the Make-facing contract';
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 2. Date-independent recommendation and range-equivalence fixture
-- ---------------------------------------------------------------------------

create temporary table migration_032_test_clock
on commit drop
as
with local_clock as (
  select (pg_catalog.now() at time zone 'America/Denver')::date as local_today
)
select
  local_today,
  (
    local_today
    + 2
    + (8 - extract(isodow from local_today + 2)::integer) % 7
  )::date as anchor_monday,
  (local_today + 2)::date as standard_start_date,
  (local_today + 23)::date as standard_end_date
from local_clock;

insert into public.organizations (
  buffer_organization_id,
  name
)
values (
  '__032_RANGE_ORG__',
  'Migration 032 isolated range fixture'
);

insert into public.channels (
  buffer_channel_id,
  buffer_organization_id,
  service,
  name,
  display_name,
  timezone,
  last_synced_at
)
select
  '__032_RANGE_CHANNEL_' || lpad(channel_number::text, 2, '0') || '__',
  '__032_RANGE_ORG__',
  'tiktok',
  '032-range-' || channel_number,
  '032 range ' || channel_number,
  'America/Denver',
  pg_catalog.now()
from generate_series(0, 8) channel_number;

insert into public.content_items (
  id,
  internal_title,
  game,
  content_type,
  vibe,
  hook_type
)
values (
  '03200000-0000-0000-1000-000000000001',
  'Migration 032 recommendation group',
  '032 Game',
  '032 Short',
  '032 Vibe',
  '032 Hook'
);

with recommendation_slots as (
  select
    slot.slot_number,
    (
      test_clock.anchor_monday
      + slot.day_offset
      - 28
      + time '12:15:00'
    )::timestamp as latest_local_sent_at
  from migration_032_test_clock test_clock
  cross join (values
    (1, 0),
    (2, 2),
    (3, 4),
    (4, -1)
  ) slot(slot_number, day_offset)
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
  last_synced_at,
  schedule_evaluated_at
)
select
  '__032_RANGE_HIST_'
    || lpad(slot.slot_number::text, 2, '0') || '_'
    || lpad(repetition.n::text, 2, '0') || '__',
  '__032_RANGE_ORG__',
  '__032_RANGE_CHANNEL_00__',
  '03200000-0000-0000-1000-000000000001'::uuid,
  'tiktok',
  'Migration 032 recommendation history',
  'sent',
  (
    slot.latest_local_sent_at
    - pg_catalog.make_interval(days => repetition.n * 7)
  ) at time zone 'America/Denver',
  (
    slot.latest_local_sent_at
    - pg_catalog.make_interval(days => repetition.n * 7)
  ) at time zone 'America/Denver',
  pg_catalog.now(),
  pg_catalog.now()
from recommendation_slots slot
cross join generate_series(0, 2) repetition(n);

insert into public.post_metric_snapshots (
  buffer_post_id,
  captured_on,
  captured_at,
  views,
  reactions,
  comments,
  shares,
  saves,
  engagement_rate
)
select
  post_record.buffer_post_id,
  current_date,
  pg_catalog.now(),
  1000,
  100,
  10,
  5,
  2,
  0.117
from public.posts post_record
where post_record.buffer_post_id like '__032_RANGE_HIST_%';

insert into public.posts (
  buffer_post_id,
  buffer_organization_id,
  buffer_channel_id,
  content_item_id,
  channel_service,
  post_text,
  status,
  due_at,
  last_synced_at,
  schedule_evaluated_at
)
select
  '__032_RANGE_CANDIDATE_' || lpad(candidate_number::text, 2, '0') || '__',
  '__032_RANGE_ORG__',
  '__032_RANGE_CHANNEL_' || lpad(candidate_number::text, 2, '0') || '__',
  '03200000-0000-0000-1000-000000000001'::uuid,
  'tiktok',
  'Migration 032 range candidate ' || candidate_number,
  'scheduled',
  (
    test_clock.anchor_monday
    + 35
    + candidate_number
    + time '19:30:00'
  ) at time zone 'America/Denver',
  pg_catalog.now() - interval '1 hour',
  null
from generate_series(1, 8) candidate_number
cross join migration_032_test_clock test_clock;

create temporary table migration_032_expected_proposals
on commit drop
as
select
  preview.buffer_post_id,
  preview.platform,
  preview.content_format,
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
  preview.timezone_name,
  row_number() over (
    order by
      preview.platform,
      preview.buffer_channel_id,
      preview.proposed_due_at_utc,
      preview.buffer_post_id
  )::integer as selection_order
from public.looker_content_aware_proposal_preview preview
where preview.buffer_post_id like '__032_RANGE_CANDIDATE_%'
  and preview.ready_to_create
  and preview.preview_status = 'Ready'
  and preview.has_active_proposal = false
  and preview.recommendation_ready_for_preview
  and preview.shadow_ready_for_live_test
  and preview.hybrid_guardrail_status = 'Pass';

do $test$
begin
  if (select count(*) from migration_032_expected_proposals) <> 8 then
    raise exception
      'Migration 032 range fixture expected eight unchanged preview rows, found %',
      (select count(*) from migration_032_expected_proposals);
  end if;
end;
$test$;


-- ---------------------------------------------------------------------------
-- 3. Shared exact-output assertion helper (temporary, transaction-local)
-- ---------------------------------------------------------------------------

create or replace function pg_temp.assert_migration_032_output(
  p_start_date date,
  p_end_date date,
  p_limit integer,
  p_expected_count integer
)
returns void
language plpgsql
as $assertion$
declare
  v_created integer;
  v_actual_count integer;
  v_difference text;
begin
  v_created := public.create_collision_safe_schedule_proposals(
    p_limit,
    p_start_date,
    p_end_date
  );

  select count(*)::integer
  into v_actual_count
  from public.schedule_change_proposals proposal
  where proposal.buffer_post_id like '__032_RANGE_CANDIDATE_%';

  if v_created <> p_expected_count
     or v_actual_count <> p_expected_count then
    raise exception
      'Range scenario created %, persisted %, expected %',
      v_created,
      v_actual_count,
      p_expected_count;
  end if;

  with expected as (
    select
      expected.buffer_post_id,
      expected.platform,
      expected.content_format,
      expected.post_text,
      expected.external_link,
      expected.current_due_at_utc,
      expected.current_due_at_local,
      expected.proposed_due_at_utc,
      expected.proposed_due_at_local,
      expected.slot_rank,
      expected.source_recommendation_rank,
      expected.recommendation_score,
      expected.confidence,
      expected.supporting_sample_size,
      expected.metrics_status,
      expected.timezone_name
    from migration_032_expected_proposals expected
    where (p_start_date is null
           or expected.proposed_due_at_local::date >= p_start_date)
      and (p_end_date is null
           or expected.proposed_due_at_local::date <= p_end_date)
    order by expected.selection_order
    limit p_limit
  ),
  actual as (
    select
      proposal.buffer_post_id,
      proposal.platform,
      proposal.content_format,
      proposal.post_text,
      proposal.external_link,
      proposal.current_due_at_utc,
      proposal.current_due_at_local,
      proposal.proposed_due_at_utc,
      proposal.proposed_due_at_local,
      proposal.slot_rank,
      proposal.source_recommendation_rank,
      proposal.recommendation_score,
      proposal.confidence,
      proposal.supporting_sample_size,
      proposal.metrics_status,
      proposal.timezone_name
    from public.schedule_change_proposals proposal
    where proposal.buffer_post_id like '__032_RANGE_CANDIDATE_%'
  ),
  differences as (
    (select * from expected except all select * from actual)
    union all
    (select * from actual except all select * from expected)
  )
  select string_agg(row(differences.*)::text, E'\n')
  into v_difference
  from differences;

  if v_difference is not null then
    raise exception
      'Optimized generator differs from unchanged preview: %',
      v_difference;
  end if;
end;
$assertion$;


-- NULL range: the manual wrapper path retains the complete preview calendar.
savepoint migration_032_null_range;
select pg_temp.assert_migration_032_output(null, null, null, 8);
rollback to savepoint migration_032_null_range;

-- Full fixed calendar range.
savepoint migration_032_full_range;
select pg_temp.assert_migration_032_output(
  (select standard_start_date from migration_032_test_clock),
  (select standard_end_date from migration_032_test_clock),
  null,
  8
);
rollback to savepoint migration_032_full_range;

-- Standard refresh contract: start + 21 is the same inclusive 22-day range.
savepoint migration_032_standard_range;
select pg_temp.assert_migration_032_output(
  (select standard_start_date from migration_032_test_clock),
  (select standard_start_date + 21 from migration_032_test_clock),
  null,
  8
);
rollback to savepoint migration_032_standard_range;

-- Partial range: match the unchanged preview on its earliest proposed day.
savepoint migration_032_partial_range;
select pg_temp.assert_migration_032_output(
  (select min(proposed_due_at_local::date)
   from migration_032_expected_proposals),
  (select min(proposed_due_at_local::date)
   from migration_032_expected_proposals),
  null,
  (
    select count(*)::integer
    from migration_032_expected_proposals
    where proposed_due_at_local::date = (
      select min(proposed_due_at_local::date)
      from migration_032_expected_proposals
    )
  )
);
rollback to savepoint migration_032_partial_range;

-- Out-of-range calls must lock/create no proposal candidates.
savepoint migration_032_out_of_range;
select pg_temp.assert_migration_032_output(
  (select standard_end_date + 30 from migration_032_test_clock),
  (select standard_end_date + 60 from migration_032_test_clock),
  null,
  0
);
rollback to savepoint migration_032_out_of_range;

-- p_limit preserves the exact first three rows in generator selection order.
savepoint migration_032_limit;
select pg_temp.assert_migration_032_output(null, null, 3, 3);
rollback to savepoint migration_032_limit;


-- ---------------------------------------------------------------------------
-- 4. Input validation, rollback, and history/evaluation preservation
-- ---------------------------------------------------------------------------

do $test$
begin
  begin
    perform public.create_collision_safe_schedule_proposals(0, null, null);
    raise exception 'p_limit=0 was not rejected';
  exception
    when others then
      if sqlerrm = 'p_limit=0 was not rejected' then
        raise;
      end if;
  end;

  begin
    perform public.create_collision_safe_schedule_proposals(
      1,
      date '2030-01-02',
      date '2030-01-01'
    );
    raise exception 'Reverse range was not rejected';
  exception
    when others then
      if sqlerrm = 'Reverse range was not rejected' then
        raise;
      end if;
  end;

  if exists (
    select 1
    from public.schedule_change_proposals proposal
    where proposal.buffer_post_id like '__032_RANGE_CANDIDATE_%'
  ) or exists (
    select 1
    from public.posts post_record
    where post_record.buffer_post_id like '__032_RANGE_CANDIDATE_%'
      and post_record.schedule_evaluated_at is not null
  ) then
    raise exception
      'A rolled-back migration-032 scenario persisted proposals or evaluation stamps';
  end if;
end;
$test$;

rollback;
