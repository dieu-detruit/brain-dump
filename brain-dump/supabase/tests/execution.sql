\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
insert into public.threads(id,user_id,title) values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','日本語の作業'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111','次の作業'),
('cccccccc-cccc-4ccc-8ccc-cccccccccccc','22222222-2222-4222-8222-222222222222','別のユーザー');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
set local role authenticated;
do $$ declare r jsonb; e jsonb; cmd jsonb; t text; begin
r:=public.apply_execution_command('{"operation_id":"10000000-0000-4000-8000-000000000001","action":"switch","expected":null,"target_thread_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}');
assert r->>'status'='applied';
e:=r->'snapshot'->'active';
cmd:=jsonb_build_object('operation_id','10000000-0000-4000-8000-000000000002','action','confirm','expected',e-'thread_id'-'last_confirmed_at'-'deadline');
r:=public.apply_execution_command(cmd); assert r->>'status'='applied';
t:=r->'snapshot'->'active'->>'last_confirmed_at';
assert public.apply_execution_command(cmd)=r,'replay changes result';
assert public.execution_snapshot()->'active'->>'last_confirmed_at'=t;
cmd:=jsonb_set(cmd,'{operation_id}','"10000000-0000-4000-8000-000000000003"');
assert public.apply_execution_command(cmd)->>'status'='stale','old revision confirmed';
assert public.sleep_unconfirmed_execution() is null,'early sleep ended execution';
e:=public.execution_snapshot()->'active';
r:=public.apply_execution_command(jsonb_build_object('operation_id',gen_random_uuid(),'action','switch','expected',e-'thread_id'-'last_confirmed_at'-'deadline','target_thread_id','cccccccc-cccc-4ccc-8ccc-cccccccccccc'));
assert r->>'status'='stale','foreign thread accepted';
end $$;
reset role;
update public.execution_sessions set last_confirmed_at=clock_timestamp()-interval '61 minutes',started_at=clock_timestamp()-interval '62 minutes' where ended_at is null;
set local role authenticated;
do $$ declare e jsonb; r jsonb; begin
 e:=public.execution_snapshot()->'active';
 r:=public.apply_execution_command(jsonb_build_object('operation_id',gen_random_uuid(),'action','confirm','expected',e-'thread_id'-'last_confirmed_at'-'deadline'));
 assert r->>'status'='expired'; assert r->'snapshot'->'active'='null'::jsonb;
end $$;
reset role;
rollback;
