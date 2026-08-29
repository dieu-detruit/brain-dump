-- Brain Dump: one private workspace per authenticated user.
create extension if not exists pgcrypto;

create table public.threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 500),
  delegation text check (delegation in ('ai', 'colleague')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.brain_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  executing_thread_id uuid references public.threads(id) on delete set null,
  updated_at timestamptz not null default now()
);

create index threads_user_created_idx on public.threads(user_id, created_at);

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger threads_set_updated_at before update on public.threads
for each row execute function public.set_updated_at();
create trigger brain_state_set_updated_at before update on public.brain_state
for each row execute function public.set_updated_at();

alter table public.threads enable row level security;
alter table public.brain_state enable row level security;

create policy "users manage own threads" on public.threads
for all to authenticated using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "users manage own state" on public.brain_state
for all to authenticated using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and (
    executing_thread_id is null
    or exists (
      select 1 from public.threads t
      where t.id = executing_thread_id and t.user_id = (select auth.uid())
    )
  )
);

grant select, insert, update, delete on public.threads to authenticated;
grant select, insert, update, delete on public.brain_state to authenticated;

-- External automations can call this RPC with the user's JWT.
create or replace function public.add_thread(thread_title text, assigned_to text default null)
returns public.threads
language plpgsql security invoker set search_path = '' as $$
declare created public.threads;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if assigned_to is not null and assigned_to not in ('ai', 'colleague') then
    raise exception 'Invalid delegation';
  end if;
  insert into public.threads (user_id, title, delegation)
  values (auth.uid(), thread_title, assigned_to)
  returning * into created;
  return created;
end;
$$;
grant execute on function public.add_thread(text, text) to authenticated;

alter publication supabase_realtime add table public.threads;
alter publication supabase_realtime add table public.brain_state;
