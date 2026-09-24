"""Concurrent PostgreSQL calls. Uses only a disposable Docker DB named by the runner."""
import subprocess, sys, time
container=sys.argv[1]
if not container.startswith('brain-dump-watch-test'): raise SystemExit('test containers only')
def sql(text):
    return subprocess.run(['docker','exec','-i',container,'psql','-U','postgres','-At','-v','ON_ERROR_STOP=1'],input=text,text=True,capture_output=True,check=True).stdout
owner='11111111-1111-4111-8111-111111111111'
setup=f"""
insert into auth.users values ('{owner}');
insert into public.threads(id,user_id,title) values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','{owner}','race'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','{owner}','second');
insert into public.brain_state(user_id,executing_thread_id) values ('{owner}','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
update public.execution_sessions set started_at=clock_timestamp()-interval '56 minutes',last_confirmed_at=clock_timestamp()-interval '55 minutes';
"""
sql(setup)
# Confirmation owns state lock. Sleep waits; after commit it must re-check the new timestamp.
command=['docker','exec','-i',container,'psql','-U','postgres','-At','-v','ON_ERROR_STOP=1']
writer=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
writer.stdin.write(f"begin; select set_config('request.jwt.claim.sub','{owner}',true); select 1 from public.brain_state where user_id='{owner}' for update; select pg_sleep(0.8); select public.apply_execution_command(jsonb_build_object('operation_id',gen_random_uuid(),'action','confirm','expected',(select jsonb_build_object('session_id',id::text,'confirmation_revision',confirmation_revision) from public.execution_sessions where ended_at is null))); commit;\n")
writer.stdin.close()
time.sleep(0.2)
result=sql(f"select set_config('request.jwt.claim.sub','{owner}',false); select public.sleep_unconfirmed_execution(); select (executing_thread_id is not null)::text from public.brain_state;")
writer.wait(timeout=10)
assert writer.returncode==0,writer.stderr.read()
assert result.strip().endswith('true'),result
# Same expected state in simultaneous switch calls: exactly one wins.
e=sql('select jsonb_build_object(\'session_id\',id::text,\'confirmation_revision\',confirmation_revision) from public.execution_sessions where ended_at is null;').strip()
import json
processes=[]
for n,target in [(1,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),(2,None)]:
    body=json.dumps(dict(operation_id=f'10000000-0000-4000-8000-{n:012d}',action='switch',expected=json.loads(e),target_thread_id=target))
    p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    p.stdin.write(f"select set_config('request.jwt.claim.sub','{owner}',false); select public.apply_execution_command('{body}') ->> 'status';\n")
    p.stdin.close();processes.append(p)
statuses=[]
for p in processes:
    p.wait(timeout=10);assert p.returncode==0,p.stderr.read();statuses.append(p.stdout.read().strip().splitlines()[-1])
assert sorted(statuses)==['applied','stale'],statuses

print('concurrent confirm/timeout and competing switches: passed')
