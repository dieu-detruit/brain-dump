create schema if not exists watch_private;
revoke all on schema watch_private from public, anon, authenticated;
alter table public.execution_sessions add column confirmation_revision uuid not null default gen_random_uuid();
create table watch_private.operations (
 user_id uuid not null references auth.users(id) on delete cascade,
 operation_id uuid not null, command jsonb not null, result jsonb not null,
 created_at timestamptz not null default clock_timestamp(), primary key(user_id,operation_id)
);
create function watch_private.snapshot(owner uuid) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('server_time',clock_timestamp(),
 'threads',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'delegation',delegation,'priority',priority) order by priority,created_at,id) from public.threads where user_id=owner),'[]'::jsonb),
 'active',(select jsonb_build_object('session_id',s.id::text,'confirmation_revision',s.confirmation_revision,'thread_id',s.thread_id,'last_confirmed_at',s.last_confirmed_at,'deadline',s.last_confirmed_at+interval '60 minutes')
 from public.execution_sessions s join public.brain_state b on b.user_id=s.user_id and b.executing_thread_id=s.thread_id
 where s.user_id=owner and s.ended_at is null));
$$;
create function public.execution_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'unauthorized'; end if;
 return watch_private.snapshot(auth.uid());
end $$;
create function watch_private.expire_execution(owner uuid) returns timestamptz
language plpgsql security definer set search_path='' as $$
declare s public.execution_sessions; begin
 perform 1 from public.brain_state where user_id=owner for update;
 select * into s from public.execution_sessions where user_id=owner and ended_at is null for update;
 if s.id is null or clock_timestamp()<s.last_confirmed_at+interval '60 minutes' then return null; end if;
 update public.execution_sessions set ended_at=last_confirmed_at where id=s.id;
 update public.brain_state set executing_thread_id=null where user_id=owner;
 return s.last_confirmed_at;
end $$;
create function watch_private.apply_command(owner uuid, command jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.execution_sessions; old watch_private.operations; op uuid; target uuid;
 result jsonb; status text:='applied'; expired timestamptz; expected jsonb; current_expected jsonb;
begin
 if owner is null then raise exception 'unauthorized'; end if;
 if command is null or jsonb_typeof(command)<>'object' or coalesce(command->>'action','') not in ('confirm','switch') or not(command ? 'expected') or command->>'operation_id' is null then raise exception 'invalid_request'; end if;
 op:=(command->>'operation_id')::uuid;
 if command->>'action'='switch' and not(command ? 'target_thread_id') then raise exception 'invalid_request'; end if;
 insert into public.brain_state(user_id) values(owner) on conflict do nothing;
 perform 1 from public.brain_state where user_id=owner for update;
 select * into old from watch_private.operations where user_id=owner and operation_id=op;
 if found then
   if old.command<>command then raise exception 'invalid_request'; end if;
   return old.result;
 end if;
 select * into s from public.execution_sessions where user_id=owner and ended_at is null for update;
 expected:=command->'expected';
 current_expected:=case when s.id is null then 'null'::jsonb else jsonb_build_object('session_id',s.id::text,'confirmation_revision',s.confirmation_revision) end;
 if expected is distinct from current_expected then status:='stale';
 else
   expired:=watch_private.expire_execution(owner);
   if expired is not null then status:='expired';
   elsif command->>'action'='confirm' then
     if s.id is null then status:='stale'; else
       update public.execution_sessions set last_confirmed_at=clock_timestamp(),confirmation_revision=gen_random_uuid() where id=s.id;
     end if;
   else
     target:=(command->>'target_thread_id')::uuid;
     -- Lock the selected thread against concurrent deletion before updating state.
     if target is not null then
       perform 1 from public.threads where id=target and user_id=owner for key share;
       if not found then status:='stale'; end if;
     end if;
     if status='applied' then
       update public.brain_state set executing_thread_id=target where user_id=owner;
     end if;
   end if;
 end if;
 result:=jsonb_build_object('status',status,'snapshot',watch_private.snapshot(owner));
 insert into watch_private.operations(user_id,operation_id,command,result) values(owner,op,command,result);
 return result;
end $$;
create function public.apply_execution_command(command jsonb) returns jsonb
language sql security definer set search_path='' as $$ select watch_private.apply_command(auth.uid(),command) $$;
-- Legacy clients remain supported, with server-side time/lock checks.
create or replace function public.sleep_unconfirmed_execution() returns timestamptz
language sql security definer set search_path='' as $$ select watch_private.expire_execution(auth.uid()) $$;
-- Old clients cannot identify the session they are confirming. Fail closed.
create or replace function public.confirm_execution() returns timestamptz
language plpgsql security definer set search_path='' as $$
begin
 raise exception 'ページを再読み込みしてから確認してください。';
end $$;
revoke all on all functions in schema watch_private from public,anon,authenticated;
revoke all on function public.execution_snapshot(),public.apply_execution_command(jsonb) from public,anon;
grant execute on function public.execution_snapshot(),public.apply_execution_command(jsonb) to authenticated;
