-- Apply manually AFTER testing deployed functions. Provision Vault secrets through Dashboard:
-- watch_notifications_url = https://PROJECT.supabase.co/functions/v1/watch-notifications
-- watch_cron_secret = same high-entropy value as Edge WATCH_CRON_SECRET
create extension if not exists pg_cron;
create extension if not exists pg_net;
create or replace function watch_private.run_notification_cron() returns void
language plpgsql security definer set search_path='' as $$
declare endpoint text; secret text; begin
 select decrypted_secret into endpoint from vault.decrypted_secrets where name='watch_notifications_url';
 select decrypted_secret into secret from vault.decrypted_secrets where name='watch_cron_secret';
 if endpoint is null or secret is null then raise exception 'Watch notification Vault settings missing'; end if;
 perform public.watch_notification_tick();
 if exists(select 1 from watch_private.notifications where state='pending' and deadline>clock_timestamp() and next_attempt_at<=clock_timestamp() and (lease_until is null or lease_until<=clock_timestamp())) then
   perform net.http_post(url:=endpoint,headers:=jsonb_build_object('Authorization','Bearer '||secret,'Content-Type','application/json'),body:='{}'::jsonb,timeout_milliseconds:=20000);
 end if;
end $$;
revoke all on function watch_private.run_notification_cron() from public,anon,authenticated;
select cron.schedule('brain-dump-watch','* * * * *','select watch_private.run_notification_cron()');
-- Stop: select cron.unschedule('brain-dump-watch');
