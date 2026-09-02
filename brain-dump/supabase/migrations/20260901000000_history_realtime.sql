-- The local history watcher uses Realtime only as a wake-up signal. It then
-- catches up by monotonically increasing ids, so reconnects cannot lose data.
alter publication supabase_realtime add table public.change_log;
alter publication supabase_realtime add table public.execution_sessions;
