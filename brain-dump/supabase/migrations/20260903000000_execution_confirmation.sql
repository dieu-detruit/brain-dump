-- Only time explicitly confirmed by the user is counted for an open session.
alter table public.execution_sessions
  add column last_confirmed_at timestamptz not null default clock_timestamp();

create function public.confirm_execution() returns timestamptz
language plpgsql security definer set search_path='' as $$
declare confirmed_at timestamptz;
begin
  update public.execution_sessions
    set last_confirmed_at=clock_timestamp()
    where user_id=auth.uid() and ended_at is null
    returning last_confirmed_at into confirmed_at;
  return confirmed_at;
end $$;

create function public.sleep_unconfirmed_execution() returns timestamptz
language plpgsql security definer set search_path='' as $$
declare confirmed_at timestamptz;
begin
  select last_confirmed_at into confirmed_at
    from public.execution_sessions
    where user_id=auth.uid() and ended_at is null
    for update;
  if confirmed_at is null then return null; end if;

  -- End at the last affirmative check-in, never at the later timeout.
  update public.execution_sessions
    set ended_at=last_confirmed_at
    where user_id=auth.uid() and ended_at is null;
  update public.brain_state
    set executing_thread_id=null
    where user_id=auth.uid() and executing_thread_id is not null;
  return confirmed_at;
end $$;

revoke all on function public.confirm_execution() from public;
revoke all on function public.sleep_unconfirmed_execution() from public;
grant execute on function public.confirm_execution() to authenticated;
grant execute on function public.sleep_unconfirmed_execution() to authenticated;
