create table watch_private.devices (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'), created_at timestamptz not null default clock_timestamp(),
 revoked_at timestamptz, push_token text, push_environment text check(push_environment in ('sandbox','production'))
);
create table watch_private.pairings (
 id uuid primary key default gen_random_uuid(), code text not null unique check(code ~ '^[0-9]{8}$'),
 secret_hash text not null unique check(secret_hash ~ '^[0-9a-f]{64}$'), token_hash text not null check(token_hash ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz not null default clock_timestamp()+interval '5 minutes', device_id uuid references watch_private.devices(id)
);
create table watch_private.rate_limits(key text primary key, started_at timestamptz not null, count integer not null);
create function watch_private.allow_request(k text, max_count integer, seconds integer) returns boolean
language plpgsql set search_path='' as $$ declare n integer; begin
 insert into watch_private.rate_limits as r values(k,clock_timestamp(),1)
 on conflict(key) do update set
 count=case when r.started_at+make_interval(secs=>seconds)<=clock_timestamp() then 1 else r.count+1 end,
 started_at=case when r.started_at+make_interval(secs=>seconds)<=clock_timestamp() then clock_timestamp() else r.started_at end
 returning count into n; return n<=max_count;
end $$;
create function public.watch_manage(action text,args jsonb,owner uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p watch_private.pairings; d uuid; result jsonb; begin
 if action='start' then
   if not watch_private.allow_request('pair-start',60,3600) then return '{"error":"rate_limited"}'; end if;
   select * into p from watch_private.pairings where secret_hash=args->>'secret_hash' for update;
   if found and (p.expires_at>clock_timestamp() or p.device_id is not null) then
     if p.token_hash<>args->>'token_hash' then return '{"error":"invalid_request"}'; end if;
     return jsonb_build_object('pairing_id',p.id,'code',p.code,'expires_at',p.expires_at);
   end if;
   delete from watch_private.pairings where expires_at<=clock_timestamp() and device_id is null;
   begin
     insert into watch_private.pairings(code,secret_hash,token_hash) values(args->>'code',args->>'secret_hash',args->>'token_hash') returning * into p;
   exception when unique_violation then return '{"error":"code_collision"}'; end;
   return jsonb_build_object('pairing_id',p.id,'code',p.code,'expires_at',p.expires_at);
 elsif action='status' then
   select * into p from watch_private.pairings where id=(args->>'pairing_id')::uuid for update;
   if not found or p.secret_hash<>args->>'secret_hash' then return '{"error":"unauthorized"}'; end if;
   if not watch_private.allow_request('poll:'||p.id,30,60) then return '{"error":"rate_limited"}'; end if;
   if p.device_id is not null then
     if not exists(select 1 from watch_private.devices where id=p.device_id and revoked_at is null) then return '{"error":"unauthorized"}'; end if;
     return jsonb_build_object('status','approved','device_id',p.device_id);
   end if;
   if p.expires_at<=clock_timestamp() then return '{"status":"expired"}'; end if;
   return jsonb_build_object('status','pending','expires_at',p.expires_at);
 end if;
 if owner is null then return '{"error":"unauthorized"}'; end if;
 if action='approve' then
   if not watch_private.allow_request('approve:'||owner,5,300) then return '{"error":"rate_limited"}'; end if;
   select * into p from watch_private.pairings where code=args->>'code' for update;
   if not found or p.expires_at<=clock_timestamp() then return '{"error":"invalid_request"}'; end if;
   if p.device_id is not null then
     if exists(select 1 from watch_private.devices where id=p.device_id and user_id=owner and revoked_at is null) then return '{"status":"approved"}'; end if;
     return '{"error":"invalid_request"}';
   end if;
   insert into watch_private.devices(user_id,token_hash) values(owner,p.token_hash) returning id into d;
   update watch_private.pairings set device_id=d where id=p.id;
   return '{"status":"approved"}';
 elsif action='devices' then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'created_at',created_at,'notifications_enabled',push_token is not null) order by created_at),'[]'::jsonb)
   into result from watch_private.devices where user_id=owner and revoked_at is null;
   return jsonb_build_object('devices',result);
 elsif action='revoke' then
   update watch_private.devices set revoked_at=clock_timestamp(),push_token=null where id=(args->>'device_id')::uuid and user_id=owner;
   if not found then return '{"error":"unauthorized"}'; end if;
   return '{"status":"revoked"}';
 end if;
 return '{"error":"invalid_request"}';
end $$;
create function public.watch_device_request(token_hash text,action text,args jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$ declare d watch_private.devices; begin
 select * into d from watch_private.devices where devices.token_hash=watch_device_request.token_hash for update;
 if not found or d.revoked_at is not null then return '{"error":"unauthorized"}'; end if;
 if not watch_private.allow_request('device:'||d.id,120,60) then return '{"error":"rate_limited"}'; end if;
 if action='state' then return watch_private.snapshot(d.user_id);
 elsif action='execution' then return watch_private.apply_command(d.user_id,args);
 elsif action='push-token' then
   if args->>'token' !~ '^[0-9a-f]{2,512}$' or length(args->>'token')%2<>0 or args->>'environment' not in ('sandbox','production') then return '{"error":"invalid_request"}'; end if;
   update watch_private.devices set push_token=args->>'token',push_environment=args->>'environment' where id=d.id;
   return '{"status":"registered"}';
 end if;
 return '{"error":"invalid_request"}';
end $$;
revoke all on all functions in schema watch_private from public,anon,authenticated;
revoke all on function public.watch_manage(text,jsonb,uuid),public.watch_device_request(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.watch_manage(text,jsonb,uuid),public.watch_device_request(text,text,jsonb) to service_role;
