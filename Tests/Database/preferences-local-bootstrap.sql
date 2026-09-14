-- Local disposable PostgreSQL only: provider role stand-ins, not a hosted migration.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
grant all on schema public to service_role;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;
