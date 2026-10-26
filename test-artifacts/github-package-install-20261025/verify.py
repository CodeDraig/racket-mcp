import concurrent.futures,hashlib,json,os,pathlib,selectors,subprocess,time
root=pathlib.Path.cwd();work=root/'.cache/github-package-install-20261025'
revision=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
url='https://github.com/CodeDraig/racket-mcp.git#main'
def verify(version,binpath):
 area=work/version;area.mkdir();home=area/'home'
 env=dict(os.environ,PLTUSERHOME=str(home),PATH=str(binpath)+os.pathsep+os.environ['PATH'])
 for key in ('PLTCOLLECTS','GITHUB_TOKEN','GH_TOKEN','GIT_ASKPASS','SSH_ASKPASS'):env.pop(key,None)
 report={'version':version,'tested_revision':revision,'steps':[],'success':False}
 def save(): (area/'results.json').write_text(json.dumps(report,indent=2)+'\n')
 def run(name,command):
  print(version,'START',name,flush=True);start=time.monotonic()
  with (area/(name+'.log')).open('wb') as f:p=subprocess.run(command,cwd=area,env=env,stdout=f,stderr=subprocess.STDOUT)
  report['steps'].append(dict(name=name,command=command,exit_code=p.returncode,seconds=round(time.monotonic()-start,3)));save()
  print(version,'DONE',name,p.returncode,flush=True)
  if p.returncode: raise RuntimeError(f'{version} {name} failed: {area/(name+".log")}')
 try:
  run('version',['racket','--version'])
  run('install',['raco','pkg','install','--auto','--batch','--no-docs','--name','racket-mcp',url])
  run('installed',['raco','pkg','show','--all','--long','--full-checksum','racket-mcp','mcp-syntax-spec-v3'])
  listing=(area/'installed.log').read_text()
  assert listing.count(revision)>=2,listing
  assert 'mcp-syntax-spec-v3*' in listing,listing
  run('cli',['raco','mcp','--help'])
  run('dependencies',['raco','setup','--check-pkg-deps','--pkgs','racket-mcp','mcp-syntax-spec-v3'])
  installed=home/'.local/share/racket'/version/'pkgs'
  sdk=installed/'racket-mcp';lang=installed/'mcp-syntax-spec-v3'
  manifest=json.loads((lang/'MCP-PATCH.json').read_text())
  for name,sha in manifest['files'].items():assert hashlib.sha256((lang/name).read_bytes()).hexdigest()==sha,name
  assert not list((sdk/'test-artifacts').rglob('*.zo')),'Archived probes compiled'
  p=subprocess.Popen(['racket',str(sdk/'examples/greeter.rkt')],cwd=area,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  responses=[]
  try:
   for i,name in enumerate(('Ada','Grace'),1):
    request={'jsonrpc':'2.0','id':i,'method':'tools/call','params':{'name':'greet','arguments':{'name':name},'_meta':{'io.modelcontextprotocol/protocolVersion':'2026-07-28','io.modelcontextprotocol/clientCapabilities':{}}}}
    p.stdin.write(json.dumps(request)+'\n');p.stdin.flush()
    with selectors.DefaultSelector() as s:
     s.register(p.stdout,selectors.EVENT_READ);assert s.select(30),'Greeter response timeout'
    response=json.loads(p.stdout.readline());responses.append(response)
    assert response['id']==i,response
    assert any(c.get('text')=='Hello, '+name for c in response['result']['content']),response
   p.stdin.close();code=p.wait(timeout=30);stderr=p.stderr.read();assert code==0,(code,stderr)
   report['greeter']={'responses':responses,'exit_code':code,'stderr':stderr}
  finally:
   if p.poll() is None:p.kill();p.wait()
  report['verified_manifest_files']=len(manifest['files'])
  report['compiled_archived_probes']=0
  report['success']=True
 finally:save()
 print(version,'PUBLIC INSTALL VERIFIED',flush=True)
 return report
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 futures=[pool.submit(verify,'9.3',root/'.cache/racket-9.3/bin'),pool.submit(verify,'9.2',root/'.cache/public-readiness-20261025/tools/racket-9.2/bin')]
 results=[f.result() for f in futures]
(work/'results.json').write_text(json.dumps(results,indent=2)+'\n')
