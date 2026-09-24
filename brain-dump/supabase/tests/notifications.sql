\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111');
insert into public.threads(id,user_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','作業');
insert into public.brain_state(user_id,executing_thread_id) values ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
insert into watch_private.devices(user_id,token_hash,push_token,push_environment) values ('11111111-1111-4111-8111-111111111111',repeat('a',64),'abcd','production');
do $$ declare jobs jsonb; j jsonb; begin
 perform public.watch_notification_tick();
 select jsonb_agg(x) into jobs from public.claim_watch_notifications(50) x;assert jobs is null,'not due yet';
 update public.execution_sessions set started_at=clock_timestamp()-interval '56 minutes',last_confirmed_at=clock_timestamp()-interval '55 minutes';
 perform public.watch_notification_tick();
 select jsonb_agg(x) into jobs from public.claim_watch_notifications(50) x;assert jsonb_array_length(jobs)=1;
 j:=jobs->0; assert public.check_watch_notification((j->>'id')::uuid,(j->>'lease_id')::uuid) is not null;
 perform public.watch_notification_tick();
 assert (select count(*) from public.claim_watch_notifications(50))=0,'lease must prevent duplicate claims';
 update public.execution_sessions set confirmation_revision=gen_random_uuid(),last_confirmed_at=clock_timestamp();
 assert public.check_watch_notification((j->>'id')::uuid,(j->>'lease_id')::uuid) is null,'old generation still sendable';
 update public.execution_sessions set last_confirmed_at=clock_timestamp()-interval '61 minutes',started_at=clock_timestamp()-interval '62 minutes';
 perform public.watch_notification_tick();
 assert (select executing_thread_id is null from public.brain_state),'expired session remains active';
end $$;
rollback;
