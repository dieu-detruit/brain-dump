\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.threads(id,user_id,title,delegation) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','作業',null),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','他人の作業',null);
insert into watch_private.devices(user_id,token_hash) values('11111111-1111-4111-8111-111111111111',repeat('a',64));
do $$ declare c jsonb; r jsonb; prior jsonb; active jsonb; session_id bigint; begin
 c:=jsonb_build_object('operation_id',gen_random_uuid(),'action','delegate','thread_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','expected',null,'expected_thread',jsonb_build_object('title','作業','delegation',null),'delegation','ai');
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='applied';
 assert (select delegation='ai' from public.threads where title='作業');
 assert public.watch_device_request(repeat('a',64),'thread',c)=r;
 -- A delayed sheet must not overwrite newer changes from the web.
 c:=jsonb_set(c,'{operation_id}',to_jsonb(gen_random_uuid()));
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='stale';
 c:=jsonb_set(c,'{expected_thread,delegation}','"ai"');
 c:=jsonb_set(c,'{operation_id}',to_jsonb(gen_random_uuid()));
 c:=jsonb_set(c,'{delegation}','"colleague"');
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='applied';
 c:=jsonb_set(c,'{expected_thread,delegation}','"colleague"');
 c:=jsonb_set(c,'{delegation}','null');
 c:=jsonb_set(c,'{operation_id}',to_jsonb(gen_random_uuid()));
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='applied';
 assert (select delegation is null from public.threads where title='作業');
 -- Start execution, then completing from an old idle sheet must fail.
 insert into public.brain_state(user_id,executing_thread_id) values('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') on conflict(user_id) do update set executing_thread_id=excluded.executing_thread_id;
 select id into session_id from public.execution_sessions where user_id='11111111-1111-4111-8111-111111111111' and ended_at is null;
 c:=jsonb_build_object('operation_id',gen_random_uuid(),'action','complete','thread_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','expected',null,'expected_thread',jsonb_build_object('title','作業','delegation',null));
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='stale';
 active:=watch_private.snapshot('11111111-1111-4111-8111-111111111111')->'active';
 c:=jsonb_set(c,'{expected}',jsonb_build_object('session_id',active->>'session_id','confirmation_revision',active->>'confirmation_revision'));
 c:=jsonb_set(c,'{operation_id}',to_jsonb(gen_random_uuid()));
 -- Foreign tasks are never modified even with a valid token and execution revision.
 prior:=c;
 c:=jsonb_set(c,'{thread_id}','"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"');
 c:=jsonb_set(c,'{expected_thread,title}','"他人の作業"');
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='stale';
 assert exists(select 1 from public.threads where title='他人の作業');
 c:=jsonb_set(prior,'{operation_id}',to_jsonb(gen_random_uuid()));
 r:=public.watch_device_request(repeat('a',64),'thread',c); assert r->>'status'='applied';
 assert not exists(select 1 from public.threads where title='作業');
 assert (select ended_at is not null and thread_title='作業' from public.execution_sessions where id=session_id);
 assert exists(select 1 from public.change_log where operation='delete' and before_data->>'title'='作業');
 assert public.watch_device_request(repeat('a',64),'thread',c)=r;
end $$;
rollback;
