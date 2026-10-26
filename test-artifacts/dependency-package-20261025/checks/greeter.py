import os,json,subprocess,selectors,pathlib
root=pathlib.Path.cwd(); work=root/'.cache/patched-package-20261025'
env=dict(os.environ,PLTUSERHOME=str(work/'home'),PATH=str(root/'.cache/racket-9.3/bin')+os.pathsep+os.environ['PATH']); env.pop('PLTCOLLECTS',None)
example=work/'home/.local/share/racket/9.3/pkgs/racket-mcp/examples/greeter.rkt'
assert example.is_file(),example
p=subprocess.Popen(['racket',str(example)],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
responses=[]
try:
 for i,name in enumerate(['Ada','Grace'],1):
  request=dict(jsonrpc='2.0',id=i,method='tools/call',params={'name':'greet','arguments':{'name':name},'_meta':{'io.modelcontextprotocol/protocolVersion':'2026-07-28','io.modelcontextprotocol/clientCapabilities':{}}})
  p.stdin.write(json.dumps(request)+'\n'); p.stdin.flush()
  with selectors.DefaultSelector() as s:
   s.register(p.stdout,selectors.EVENT_READ)
   assert s.select(30),'greeter response timeout'
  response=json.loads(p.stdout.readline()); responses.append(response)
  assert response['id']==i,response
  assert any(item.get('text')=='Hello, '+name for item in response['result']['content']),response
 p.stdin.close(); code=p.wait(timeout=30); error=p.stderr.read()
 assert code==0,(code,error)
 (work/'greeter.json').write_text(json.dumps(dict(responses=responses,exit_code=code,stderr=error),indent=2)+'\n')
 print('Installed-package greeter: Ada and Grace passed; EOF exit 0')
finally:
 if p.poll() is None: p.kill(); p.wait()
