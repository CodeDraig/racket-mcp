import json, os, pathlib, signal, socket, subprocess, tempfile, time, hashlib
root=pathlib.Path.cwd()
out=root/'test-artifacts/declared-core-20260908'
harness=pathlib.Path('/tmp/racket-mcp-conformance-elicitation-20260907')
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
 server_argv=['racket',str(root/'dev/conformance-list-changes.rkt'),str(port),str(pathlib.Path(temp)/'state.sqlite')]
 argv=[str(harness/'node_modules/.bin/tsx'),str(harness/'src/index.ts'),'server','--url',f'http://127.0.0.1:{port}/mcp','--requirements','2026-07-28','--output-dir',str(out/'results'),'--timeout','60000']
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
   result=subprocess.run(argv,cwd=harness,stdout=harness_log,stderr=subprocess.STDOUT)
   (out/'exit.json').write_text(json.dumps({'harness':result.returncode})+'\n')
  finally:
   if server.poll() is None:
    os.killpg(server.pid,signal.SIGINT)
    try: server.wait(timeout=10)
    except subprocess.TimeoutExpired:
     os.killpg(server.pid,signal.SIGKILL); server.wait()
   (out/'server-exit.json').write_text(json.dumps({'code':server.returncode})+'\n')
