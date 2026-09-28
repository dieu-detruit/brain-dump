-- PostgreSQL bounded regex repetitions cannot exceed 255. Check token length
-- separately so valid APNs tokens do not raise instead of being registered.
create or replace function public.watch_device_request(token_hash text,action text,args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d watch_private.devices; begin
 select * into d from watch_private.devices where devices.token_hash=watch_device_request.token_hash for update;
 if not found or d.revoked_at is not null then return '{"error":"unauthorized"}'; end if;
 if not watch_private.allow_request('device:'||d.id,120,60) then return '{"error":"rate_limited"}'; end if;
 if action='state' then return watch_private.snapshot(d.user_id);
 elsif action='execution' then return watch_private.apply_command(d.user_id,args);
 elsif action='push-token' then
   if jsonb_typeof(args->'token') is distinct from 'string'
      or jsonb_typeof(args->'environment') is distinct from 'string'
      or length(args->>'token') not between 2 and 512
      or args->>'token' !~ '^[0-9a-f]+$'
      or length(args->>'token')%2<>0
      or args->>'environment' not in ('sandbox','production') then
     return '{"error":"invalid_request"}';
   end if;
   update watch_private.devices set push_token=args->>'token',push_environment=args->>'environment' where id=d.id;
   return '{"status":"registered"}';
 end if;
 return '{"error":"invalid_request"}';
end $$;
