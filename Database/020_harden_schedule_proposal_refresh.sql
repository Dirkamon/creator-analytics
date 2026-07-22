begin;

do $$
declare
  v_oid oid;
  v_def text;
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

  -- Skip proposals where the recommended time is already
  -- the post's current scheduled time.
  if v_def !~* 'from[[:space:]]+paired[[:space:]]+where[[:space:]]+current_due_at_utc[[:space:]]+is[[:space:]]+distinct[[:space:]]+from[[:space:]]+proposed_due_at_utc'
  then
    if v_def !~* 'from[[:space:]]+paired' then
      raise exception
        'Expected FROM paired clause was not found. Function was not changed.';
    end if;

    v_def := regexp_replace(
      v_def,
      'from[[:space:]]+paired',
      E'from paired\n    where current_due_at_utc is distinct from proposed_due_at_utc',
      'i'
    );
  end if;

  -- Only Pending proposals may be refreshed.
  -- Approved proposals stay frozen until applied.
  if v_def !~* 'public\.schedule_change_proposals\.approval_status[[:space:]]*=[[:space:]]*''Pending'''
  then
    if v_def !~* 'public\.schedule_change_proposals\.approval_status[[:space:]]+not[[:space:]]+in[[:space:]]*\([[:space:]]*''Applied''[[:space:]]*\)'
    then
      raise exception
        'Expected proposal-status WHERE clause was not found. Function was not changed.';
    end if;

    v_def := regexp_replace(
      v_def,
      'where[[:space:]]+public\.schedule_change_proposals\.approval_status[[:space:]]+not[[:space:]]+in[[:space:]]*\([[:space:]]*''Applied''[[:space:]]*\)[[:space:]]*;',
      'where public.schedule_change_proposals.approval_status = ''Pending'';',
      'i'
    );
  end if;

  execute v_def;
end
$$;

commit;