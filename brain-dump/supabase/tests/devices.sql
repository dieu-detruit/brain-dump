\set ON_ERROR_STOP on
begin;
insert into auth.users values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
do $$ declare p jsonb; r jsonb; id text; begin
p:=public.watch_manage('start',jsonb_build_object('secret_hash',repeat('a',64),'token_hash',repeat('b',64),'code','12345678'));
id:=p->>'pairing_id'; assert id is not null;
r:=public.watch_manage('approve','{"code":"12345678"}','11111111-1111-4111-8111-111111111111'); assert r->>'status'='approved';
r:=public.watch_manage('status',jsonb_build_object('pairing_id',id,'secret_hash',repeat('c',64))); assert r->>'error'='unauthorized';
r:=public.watch_manage('status',jsonb_build_object('pairing_id',id,'secret_hash',repeat('a',64))); assert r->>'status'='approved';
assert public.watch_manage('status',jsonb_build_object('pairing_id',id,'secret_hash',repeat('a',64)))=r;
id:=r->>'device_id';
r:=public.watch_manage('revoke',jsonb_build_object('device_id',id),'22222222-2222-4222-8222-222222222222'); assert r->>'error'='unauthorized';
r:=public.watch_device_request(repeat('b',64),'state','{}'); assert r ? 'threads';
r:=public.watch_manage('revoke',jsonb_build_object('device_id',id),'11111111-1111-4111-8111-111111111111'); assert r->>'status'='revoked';
r:=public.watch_device_request(repeat('b',64),'state','{}'); assert r->>'error'='unauthorized';
end $$;
rollback;
