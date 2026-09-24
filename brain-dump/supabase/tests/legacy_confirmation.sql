\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111');
insert into public.threads(id,user_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','作業');
insert into public.brain_state(user_id,executing_thread_id) values ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
set local role authenticated;
do $$ declare rejected boolean:=false; begin
 begin perform public.confirm_execution(); exception when raise_exception then rejected:=true; end;
 assert rejected,'parameterless legacy confirmation must require page reload';
end $$;
rollback;
