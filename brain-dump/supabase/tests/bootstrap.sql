create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create role anon;
create role authenticated;
create role service_role bypassrls;
grant usage on schema auth to authenticated,service_role;
create publication supabase_realtime;
