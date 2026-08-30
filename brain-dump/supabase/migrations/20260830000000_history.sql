create table public.change_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null check (entity_type in ('thread','brain_state')),
  entity_id uuid not null,
  operation text not null check (operation in ('insert','update','delete')),
  changed_at timestamptz not null default clock_timestamp(),
  before_data jsonb,
  after_data jsonb
);
create table public.execution_sessions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  thread_id uuid not null,
  thread_title text not null,
  started_at timestamptz not null default clock_timestamp(),
  ended_at timestamptz check (ended_at is null or ended_at >= started_at)
);
create index change_log_user_changed_idx on public.change_log(user_id,changed_at,id);
create index execution_sessions_user_started_idx on public.execution_sessions(user_id,started_at,id);
create unique index execution_sessions_one_open_per_user on public.execution_sessions(user_id) where ended_at is null;
alter table public.change_log enable row level security;
alter table public.execution_sessions enable row level security;
create policy "users read own change log" on public.change_log for select to authenticated using ((select auth.uid())=user_id);
create policy "users read own execution sessions" on public.execution_sessions for select to authenticated using ((select auth.uid())=user_id);
grant select on public.change_log, public.execution_sessions to authenticated;

create function public.record_thread_change() returns trigger language plpgsql security definer set search_path='' as $$
declare owner_id uuid; target_id uuid;
begin
  owner_id:=case when tg_op='DELETE' then old.user_id else new.user_id end;
  target_id:=case when tg_op='DELETE' then old.id else new.id end;
  insert into public.change_log(user_id,entity_type,entity_id,operation,before_data,after_data)
  values(owner_id,'thread',target_id,lower(tg_op),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old)-'user_id' end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new)-'user_id' end);
  return case when tg_op='DELETE' then old else new end;
end $$;

create function public.record_execution_change() returns trigger language plpgsql security definer set search_path='' as $$
declare previous_id uuid; next_title text;
begin
  previous_id:=case when tg_op='INSERT' then null else old.executing_thread_id end;
  if previous_id is not distinct from new.executing_thread_id then return new; end if;
  update public.execution_sessions set ended_at=clock_timestamp() where user_id=new.user_id and ended_at is null;
  if new.executing_thread_id is not null then
    select title into strict next_title from public.threads where id=new.executing_thread_id and user_id=new.user_id;
    insert into public.execution_sessions(user_id,thread_id,thread_title) values(new.user_id,new.executing_thread_id,next_title);
  end if;
  insert into public.change_log(user_id,entity_type,entity_id,operation,before_data,after_data)
  values(new.user_id,'brain_state',new.user_id,case when tg_op='INSERT' then 'insert' else 'update' end,
    case when tg_op='UPDATE' then jsonb_build_object('executing_thread_id',old.executing_thread_id) end,
    jsonb_build_object('executing_thread_id',new.executing_thread_id));
  return new;
end $$;
revoke all on function public.record_thread_change() from public;
revoke all on function public.record_execution_change() from public;
create trigger threads_record_change after insert or update or delete on public.threads for each row execute function public.record_thread_change();
create trigger brain_state_record_execution_change after insert or update of executing_thread_id on public.brain_state for each row execute function public.record_execution_change();
