-- Creator Analytics
-- Normalize proposal-preview service-role permissions
-- File: Database/030_normalize_proposal_preview_service_role_permissions.sql
--
-- Migration 029 preserved pre-existing service_role ACL entries when it used
-- CREATE OR REPLACE VIEW. Normalize only that role on the two proposal-preview
-- views, then fail closed unless the complete direct non-owner ACL is exact.

begin;

revoke all privileges on table
  public.looker_content_aware_proposal_preview,
  public.looker_content_aware_proposal_preview_summary
from service_role;

grant select on table
  public.looker_content_aware_proposal_preview,
  public.looker_content_aware_proposal_preview_summary
to service_role;

do $migration_030_acl$
declare
  v_actual_contract text[];
  v_expected_contract text[];
begin
  select array_agg(
    format(
      '%s:%s:%s:%s',
      relation.relname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      case when acl.is_grantable then 'YES' else 'NO' end
    )
    order by
      relation.relname,
      case
        when acl.grantee = 0::oid then 'PUBLIC'
        else coalesce(grantee.rolname, 'OID ' || acl.grantee::text)
      end,
      acl.privilege_type,
      acl.is_grantable
  )
  into v_actual_contract
  from pg_class relation
  join pg_namespace namespace
    on namespace.oid = relation.relnamespace
  cross join lateral aclexplode(
    coalesce(relation.relacl, acldefault('r', relation.relowner))
  ) acl
  left join pg_roles grantee
    on grantee.oid = acl.grantee
  where namespace.nspname = 'public'
    and relation.relkind = 'v'
    and relation.relname in (
      'looker_content_aware_proposal_preview',
      'looker_content_aware_proposal_preview_summary'
    )
    and acl.grantee <> relation.relowner;

  select array_agg(
    format(
      '%s:%s:%s:%s',
      expected.view_name,
      expected.grantee_name,
      expected.privilege_type,
      expected.is_grantable
    )
    order by
      expected.view_name,
      expected.grantee_name,
      expected.privilege_type,
      expected.is_grantable
  )
  into v_expected_contract
  from (values
    (
      'looker_content_aware_proposal_preview'::text,
      'creator_dashboard_reader'::text,
      'SELECT'::text,
      'NO'::text
    ),
    (
      'looker_content_aware_proposal_preview',
      'service_role',
      'SELECT',
      'NO'
    ),
    (
      'looker_content_aware_proposal_preview_summary',
      'creator_dashboard_reader',
      'SELECT',
      'NO'
    ),
    (
      'looker_content_aware_proposal_preview_summary',
      'service_role',
      'SELECT',
      'NO'
    )
  ) expected(
    view_name,
    grantee_name,
    privilege_type,
    is_grantable
  );

  if v_actual_contract is distinct from v_expected_contract then
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 030 proposal-preview ACL mismatch: actual %s; expected %s',
        coalesce(v_actual_contract::text, 'NULL'),
        v_expected_contract::text
      );
  end if;
end;
$migration_030_acl$;

commit;
