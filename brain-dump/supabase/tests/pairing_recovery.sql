\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111');
do $$ declare p jsonb; r jsonb; begin
p:=public.watch_manage('start',jsonb_build_object('secret_hash',repeat('a',64),'token_hash',repeat('b',64),'code','12345678'));
perform public.watch_manage('approve','{"code":"12345678"}','11111111-1111-4111-8111-111111111111');
update watch_private.pairings set expires_at=clock_timestamp()-interval '10 minutes';
r:=public.watch_manage('status',jsonb_build_object('pairing_id',p->>'pairing_id','secret_hash',repeat('a',64)));
assert r->>'status'='approved','approved pairing must survive display-code expiry';
perform public.watch_manage('start',jsonb_build_object('secret_hash',repeat('c',64),'token_hash',repeat('d',64),'code','87654321'));
r:=public.watch_manage('status',jsonb_build_object('pairing_id',p->>'pairing_id','secret_hash',repeat('a',64)));
assert r->>'status'='approved','new pairing cleaned up recoverable approval';
end $$;
rollback;
