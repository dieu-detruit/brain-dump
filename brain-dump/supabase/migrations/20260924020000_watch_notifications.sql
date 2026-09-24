create table watch_private.notifications (
 id uuid primary key default gen_random_uuid(), device_id uuid not null references watch_private.devices(id) on delete cascade,
 session_id bigint not null references public.execution_sessions(id) on delete cascade, confirmation_revision uuid not null,
 operation_id uuid not null default gen_random_uuid(), deadline timestamptz not null,
 state text not null default 'pending' check(state in ('pending','sent','cancelled','configuration_error')),
 lease_id uuid, lease_until timestamptz, next_attempt_at timestamptz not null default clock_timestamp(),
 unique(device_id,session_id,confirmation_revision)
);
create function public.watch_notification_tick() returns integer
language plpgsql security definer set search_path='' as $$ declare owner uuid; n integer; begin
 for owner in select distinct d.user_id from watch_private.devices d where revoked_at is null order by d.user_id loop
   perform watch_private.expire_execution(owner);
 end loop;
 insert into watch_private.notifications(device_id,session_id,confirmation_revision,deadline)
 select d.id,s.id,s.confirmation_revision,s.last_confirmed_at+interval '60 minutes'
 from public.execution_sessions s join watch_private.devices d on d.user_id=s.user_id
 where s.ended_at is null and d.revoked_at is null and d.push_token is not null
 and s.last_confirmed_at+interval '55 minutes'<=clock_timestamp()
 and s.last_confirmed_at+interval '60 minutes'>clock_timestamp()
 and not exists(select 1 from watch_private.notifications n where n.device_id=d.id and n.session_id=s.id and n.confirmation_revision=s.confirmation_revision)
 on conflict do nothing;
 get diagnostics n=row_count;
 -- Housekeeping is bounded by personal-app volume and indexed time columns.
 delete from watch_private.operations where created_at<clock_timestamp()-interval '7 days';
 delete from watch_private.notifications where deadline<clock_timestamp()-interval '7 days';
 delete from watch_private.pairings where expires_at<clock_timestamp()-interval '1 day' and (device_id is null or exists(select 1 from watch_private.devices d where d.id=pairings.device_id and d.revoked_at is not null));
 delete from watch_private.rate_limits where started_at<clock_timestamp()-interval '1 day';
 return n;
end $$;
create function public.claim_watch_notifications(batch_size integer default 50) returns setof jsonb
language plpgsql security definer set search_path='' as $$ begin
 return query with candidates as (
 select n.id from watch_private.notifications n
 join watch_private.devices d on d.id=n.device_id
 join public.execution_sessions s on s.id=n.session_id
 where n.state='pending' and n.deadline>clock_timestamp() and n.next_attempt_at<=clock_timestamp()
 and (n.lease_until is null or n.lease_until<=clock_timestamp())
 and d.revoked_at is null and d.push_token is not null and s.ended_at is null and s.confirmation_revision=n.confirmation_revision
 order by n.deadline limit least(greatest(batch_size,1),50) for update of n skip locked
 ), claimed as (
 update watch_private.notifications n set lease_id=gen_random_uuid(),lease_until=clock_timestamp()+interval '30 seconds'
 from candidates c where n.id=c.id returning n.*
 ) select jsonb_build_object('id',c.id,'lease_id',c.lease_id) from claimed c;
end $$;
create function public.check_watch_notification(job_id uuid,lease uuid) returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('id',n.id,'lease_id',n.lease_id,'device_id',d.id,'push_token',d.push_token,'push_environment',d.push_environment,
 'session_id',s.id::text,'confirmation_revision',n.confirmation_revision,'operation_id',n.operation_id,
 'thread_title',t.title,'deadline',n.deadline,'collapse_id',encode(sha256(convert_to(n.id::text,'UTF8')),'hex'))
 from watch_private.notifications n join watch_private.devices d on d.id=n.device_id
 join public.execution_sessions s on s.id=n.session_id join public.threads t on t.id=s.thread_id
 where n.id=job_id and n.lease_id=lease and n.lease_until>clock_timestamp() and n.state='pending'
 and n.deadline>clock_timestamp() and d.revoked_at is null and d.push_token is not null
 and s.ended_at is null and s.confirmation_revision=n.confirmation_revision;
$$;
create function public.finish_watch_notification(job_id uuid,lease uuid,outcome text) returns void
language sql security definer set search_path='' as $$
 update watch_private.notifications set
 state=case outcome when 'sent' then 'sent' when 'configuration_error' then 'configuration_error' when 'invalid_token' then 'cancelled' else 'pending' end,
 next_attempt_at=clock_timestamp()+interval '60 seconds',lease_until=null,lease_id=null
 where id=job_id and lease_id=lease;
$$;
-- Separate transaction from finishing a job to avoid queue/device lock inversion.
create function public.invalidate_watch_push_token(device uuid,token text) returns void
language sql security definer set search_path='' as $$
 update watch_private.devices set push_token=null where id=device and push_token=token;
$$;
revoke all on function public.watch_notification_tick(),public.claim_watch_notifications(integer),public.check_watch_notification(uuid,uuid),public.finish_watch_notification(uuid,uuid,text),public.invalidate_watch_push_token(uuid,text) from public,anon,authenticated;
grant execute on function public.watch_notification_tick(),public.claim_watch_notifications(integer),public.check_watch_notification(uuid,uuid),public.finish_watch_notification(uuid,uuid,text),public.invalidate_watch_push_token(uuid,text) to service_role;
create index operations_created_idx on watch_private.operations(created_at);
create index notifications_due_idx on watch_private.notifications(next_attempt_at,deadline) where state='pending';
