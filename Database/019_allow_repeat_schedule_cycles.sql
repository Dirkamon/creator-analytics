begin;

-- Remove the old rule that only allowed one proposal ever
-- for each Buffer post.
alter table public.schedule_change_proposals
drop constraint if exists schedule_change_proposals_buffer_post_id_key;

-- Allow unlimited historical proposals, but only one active
-- Pending/Approved proposal for a Buffer post at a time.
create unique index if not exists
schedule_change_proposals_one_active_per_post_idx
on public.schedule_change_proposals (buffer_post_id)
where approval_status in ('Pending', 'Approved');

-- Update refresh_schedule_proposals() so its UPSERT targets
-- the active-proposal partial unique index.
do $$
declare
  v_oid oid;
  v_def text;
  v_old text := 'on conflict (buffer_post_id)';
  v_new text :=
    'on conflict (buffer_post_id) where approval_status in (''Pending'', ''Approved'')';
begin
  select p.oid
    into v_oid
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'refresh_schedule_proposals';

  if v_oid is null then
    raise exception 'refresh_schedule_proposals function was not found';
  end if;

  v_def := pg_get_functiondef(v_oid);

  if position(v_old in lower(v_def)) = 0 then
    raise exception
      'Expected ON CONFLICT clause was not found. Function was not changed.';
  end if;

  v_def := replace(v_def, v_old, v_new);

  execute v_def;
end
$$;

commit;