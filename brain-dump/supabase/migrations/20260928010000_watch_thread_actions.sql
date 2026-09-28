create function watch_private.apply_thread_command(owner uuid, command jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t public.threads; s public.execution_sessions; old watch_private.operations;
 op uuid; result jsonb; status text:='applied'; current_expected jsonb;
begin
 if owner is null then raise exception 'unauthorized'; end if;
 if command is null or jsonb_typeof(command)<>'object'
    or coalesce(command->>'action','') not in ('complete','delegate')
    or command->>'operation_id' is null or command->>'thread_id' is null
    or not(command ? 'expected')
    or jsonb_typeof(command->'expected_thread') is distinct from 'object'
    or jsonb_typeof(command->'expected_thread'->'title') is distinct from 'string'
    or not(command->'expected_thread' ? 'delegation') then raise exception 'invalid_request'; end if;
 if command->>'action'='delegate' and
    (not(command ? 'delegation') or (command->'delegation'<>'null'::jsonb and command->>'delegation' not in ('ai','colleague'))) then
   raise exception 'invalid_request';
 end if;
 op:=(command->>'operation_id')::uuid;
 insert into public.brain_state(user_id) values(owner) on conflict do nothing;
 -- Same lock order as execution commands; duplicate operations are serialized.
 perform 1 from public.brain_state where user_id=owner for update;
 select * into old from watch_private.operations where user_id=owner and operation_id=op;
 if found then
   if old.command<>command then raise exception 'invalid_request'; end if;
   return old.result;
 end if;
 select * into s from public.execution_sessions where user_id=owner and ended_at is null for update;
 current_expected:=case when s.id is null then 'null'::jsonb else jsonb_build_object('session_id',s.id::text,'confirmation_revision',s.confirmation_revision) end;
 select * into t from public.threads where user_id=owner and id=(command->>'thread_id')::uuid for update;
 if t.id is null or command->'expected' is distinct from current_expected
    or command->'expected_thread' is distinct from jsonb_build_object('title',t.title,'delegation',t.delegation) then
   status:='stale';
 else
   if command->>'action'='complete' then
     -- Preserve the timeout rule and existing history/delete triggers.
     perform watch_private.expire_execution(owner);
     delete from public.threads where id=t.id and user_id=owner;
   else
     update public.threads set delegation=command->>'delegation' where id=t.id and user_id=owner;
   end if;
 end if;
 result:=jsonb_build_object('status',status,'snapshot',watch_private.snapshot(owner));
 insert into watch_private.operations(user_id,operation_id,command,result) values(owner,op,command,result);
 return result;
end $$;
revoke all on function watch_private.apply_thread_command(uuid,jsonb) from public,anon,authenticated;

create or replace function public.watch_device_request(token_hash text,action text,args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d watch_private.devices; begin
 select * into d from watch_private.devices where devices.token_hash=watch_device_request.token_hash for update;
 if not found or d.revoked_at is not null then return '{"error":"unauthorized"}'; end if;
 if not watch_private.allow_request('device:'||d.id,120,60) then return '{"error":"rate_limited"}'; end if;
 if action='state' then return watch_private.snapshot(d.user_id);
 elsif action='execution' then return watch_private.apply_command(d.user_id,args);
 elsif action='thread' then return watch_private.apply_thread_command(d.user_id,args);
 elsif action='push-token' then
   if jsonb_typeof(args->'token') is distinct from 'string'
      or jsonb_typeof(args->'environment') is distinct from 'string'
      or length(args->>'token') not between 2 and 512
      or args->>'token' !~ '^[0-9a-f]+$'
      or length(args->>'token')%2<>0
      or args->>'environment' not in ('sandbox','production') then return '{"error":"invalid_request"}'; end if;
   update watch_private.devices set push_token=args->>'token',push_environment=args->>'environment' where id=d.id;
   return '{"status":"registered"}';
 end if;
 return '{"error":"invalid_request"}';
end $$;
