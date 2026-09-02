-- A smaller number means a higher priority.  Gaps allow a drag-and-drop move
-- to update only the moved thread, which keeps the audit trail readable.
alter table public.threads add column priority double precision not null default 0;

-- Backfilling is a schema migration, not a user-initiated reorder, so it must
-- not create misleading entries in the change log.
alter table public.threads disable trigger threads_record_change;
with ranked as (
  select id, row_number() over (partition by user_id order by created_at, id) * 1024 as priority
  from public.threads
)
update public.threads as threads
set priority = ranked.priority
from ranked
where threads.id = ranked.id;
alter table public.threads enable trigger threads_record_change;

create index threads_user_priority_idx on public.threads(user_id, priority, created_at);

-- API clients that do not know about priorities still place new threads at the
-- end of their own list.
create function public.set_thread_priority()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.priority = 0 then
    select coalesce(max(priority), 0) + 1024 into new.priority
    from public.threads where user_id = new.user_id;
  end if;
  return new;
end;
$$;

create trigger threads_set_priority before insert on public.threads
for each row execute function public.set_thread_priority();
