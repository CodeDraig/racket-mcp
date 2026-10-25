import json, os, pathlib, signal, socket, subprocess, tempfile, time, hashlib
root=pathlib.Path('/srv/data/code/racket-mcp/.cache/public-readiness-20261025/racket-9.3-corrected')
out=pathlib.Path('/srv/data/code/racket-mcp/.cache/public-readiness-20261025/conformance-retry/tasks')
harness=pathlib.Path('/srv/data/code/racket-mcp/.cache/conformance-pinned')
vendored=root/'vendor/conformance'
files=[*list((vendored/'src').rglob('*')),*list((vendored/'requirements').rglob('*')),vendored/'package.json',vendored/'package-lock.json']
checked=[]
for p in files:
 if p.is_file():
  rel=p.relative_to(vendored)
  digest=hashlib.sha256(p.read_bytes()).hexdigest()
  assert digest==hashlib.sha256((harness/rel).read_bytes()).hexdigest(), str(rel)
  checked.append({'file':str(rel),'sha256':digest})
(out/'harness-inputs.json').write_text(json.dumps(checked,indent=2)+'\n')
with tempfile.TemporaryDirectory(prefix='mcp-conformance-state-') as temp:
 with socket.socket() as listener:
  listener.bind(('127.0.0.1',0)); port=listener.getsockname()[1]
 server_argv=['racket',str(root/'mcp/command.rkt'),'--build-id','conformance-declared/1','--transport','http','--port',str(port),'--state',str(pathlib.Path(temp)/'state.sqlite'),'serve',str(root/'dev/conformance-tasks.rkt')]
 argv=[str(harness/'node_modules/.bin/tsx'),str(harness/'src/index.ts'),'server','--url',f'http://127.0.0.1:{port}/mcp','--scenario','tasks-*','--spec-version','2026-07-28','--force','--output-dir',str(out/'results'),'--timeout','60000']
 (out/'commands.json').write_text(json.dumps({'server':server_argv,'harness':argv},indent=2)+'\n')
 with (out/'server.log').open('w') as server_log, (out/'harness.log').open('w') as harness_log:
  server=subprocess.Popen(server_argv,stdout=server_log,stderr=subprocess.STDOUT,start_new_session=True)
  try:
   deadline=time.monotonic()+30
   while True:
    if server.poll() is not None: raise RuntimeError(f'server exited {server.returncode}')
    try:
     with socket.create_connection(('127.0.0.1',port),timeout=.25): break
    except OSError:
     if time.monotonic()>deadline: raise RuntimeError('server startup exceeded 30 seconds')
     time.sleep(.05)
   scenarios=['tasks-lifecycle','tasks-capability-negotiation','tasks-wire-fields',
    'tasks-request-state-removal','tasks-mrtr-input','tasks-request-headers',
    'tasks-dispatch-and-envelope','tasks-status-notifications','tasks-required-task-error','tasks-mrtr-composition']
   exits={}
   for scenario in scenarios:
    call=[scenario if arg=='tasks-*' else arg for arg in argv]
    result=subprocess.run(call,cwd=harness,stdout=harness_log,stderr=subprocess.STDOUT)
    exits[scenario]=result.returncode
    (out/'scenario-exits.json').write_text(json.dumps(exits,indent=2)+'\n')
  finally:
   if server.poll() is None:
    os.killpg(server.pid,signal.SIGINT)
    try: server.wait(timeout=10)
    except subprocess.TimeoutExpired:
     os.killpg(server.pid,signal.SIGKILL); server.wait()
   (out/'server-exit.json').write_text(json.dumps({'code':server.returncode})+'\n')
