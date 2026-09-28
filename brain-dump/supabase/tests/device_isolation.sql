\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.threads(id,user_id,title) values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','Alice private'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','Bob private');
do $$ declare a jsonb; b jsonb; before_b jsonb; result jsonb; expected_a jsonb; begin
perform public.watch_manage('start',jsonb_build_object('secret_hash',repeat('a',64),'token_hash',repeat('b',64),'code','12345678'));
perform public.watch_manage('start',jsonb_build_object('secret_hash',repeat('c',64),'token_hash',repeat('d',64),'code','87654321'));
perform public.watch_manage('approve','{"code":"12345678"}','11111111-1111-4111-8111-111111111111');
perform public.watch_manage('approve','{"code":"87654321"}','22222222-2222-4222-8222-222222222222');
assert public.watch_manage('approve','{"code":"12345678"}','22222222-2222-4222-8222-222222222222')->>'error'='invalid_request', 'pairing stolen';
a:=public.watch_device_request(repeat('b',64),'state','{}');
b:=public.watch_device_request(repeat('d',64),'state','{}');
assert jsonb_array_length(a->'threads')=1 and a->'threads'->0->>'title'='Alice private', 'Alice read foreign data';
assert jsonb_array_length(b->'threads')=1 and b->'threads'->0->>'title'='Bob private', 'Bob read foreign data';
result:=public.watch_device_request(repeat('d',64),'execution',jsonb_build_object('operation_id',gen_random_uuid(),'action','switch','expected',null,'target_thread_id','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));
assert result->>'status'='applied'; before_b:=result->'snapshot'->'active';
result:=public.watch_device_request(repeat('b',64),'execution',jsonb_build_object('operation_id',gen_random_uuid(),'action','switch','expected',null,'target_thread_id','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'));
assert result->>'status'='stale', 'Alice switched to foreign thread';
result:=public.watch_device_request(repeat('b',64),'execution',jsonb_build_object('operation_id',gen_random_uuid(),'action','confirm','expected',before_b-'thread_id'-'last_confirmed_at'-'deadline'));
assert result->>'status'='stale', 'Alice confirmed foreign session';
assert public.watch_device_request(repeat('d',64),'state','{}')->'active'=before_b, 'foreign session changed';
result:=public.watch_device_request(repeat('b',64),'execution',jsonb_build_object('operation_id',gen_random_uuid(),'action','switch','expected',null,'target_thread_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'));
assert result->>'status'='applied'; expected_a:=result->'snapshot'->'active';
result:=public.watch_device_request(repeat('b',64),'execution',jsonb_build_object('operation_id',gen_random_uuid(),'action','confirm','expected',expected_a-'thread_id'-'last_confirmed_at'-'deadline'));
assert result->>'status'='applied', 'own confirmation rejected';
assert public.watch_device_request(repeat('d',64),'state','{}')->'active'=before_b, 'own operation changed other user';
end $$;
rollback;
