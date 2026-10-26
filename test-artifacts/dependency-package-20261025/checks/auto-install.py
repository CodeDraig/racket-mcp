import functools,http.server,threading,pathlib,zipfile,os,subprocess,json,time,hashlib,shutil
root=pathlib.Path.cwd(); work=root/'.cache/patched-package-20261025'; directory=work/'auto-install'; directory.mkdir()
delivery=directory/'delivery';delivery.mkdir()
shutil.copy2(work/'mcp-syntax-spec-v3.zip',delivery/'mcp-syntax-spec-v3.zip')
requests=[]
class Handler(http.server.SimpleHTTPRequestHandler):
 def log_message(self,fmt,*args): requests.append(fmt%args)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(Handler,directory=str(delivery)))
thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
port=server.server_port
old=b'https://github.com/CodeDraig/racket-mcp.git?path=packages/mcp-syntax-spec-v3#main'
new=f'http://127.0.0.1:{port}/mcp-syntax-spec-v3.zip'.encode()
archive=work/'final-distribution-source/.cache/distribution/racket-mcp-0.1.zip'
with zipfile.ZipFile(archive) as src,zipfile.ZipFile(delivery/'racket-mcp.zip','w',compression=zipfile.ZIP_DEFLATED) as dst:
 for entry in src.infolist():
  data=src.read(entry.filename)
  if entry.filename=='racket-mcp/info.rkt':
   assert data.count(old)==1;data=data.replace(old,new)
  dst.writestr(entry,data)
env=dict(os.environ,PLTUSERHOME=str(directory/'home'),PATH=str(root/'.cache/racket-9.3/bin')+os.pathsep+os.environ['PATH']);env.pop('PLTCOLLECTS',None)
cmd=['raco','pkg','install','--auto','--batch','--no-docs',f'http://127.0.0.1:{port}/racket-mcp.zip']
start=time.monotonic()
try:
 print('START automatic URL dependency install',flush=True)
 with (directory/'install.log').open('wb') as log:p=subprocess.run(cmd,cwd=directory,env=env,stdout=log,stderr=subprocess.STDOUT)
 report=dict(command=cmd,exit_code=p.returncode,seconds=round(time.monotonic()-start,2),substitution={'from':old.decode(),'to':new.decode(),'scope':'Only dependency source URL in test SDK archive; all dependency ZIP bytes and SDK code unchanged.'},requests=requests,dependency_sha256=hashlib.sha256((delivery/'mcp-syntax-spec-v3.zip').read_bytes()).hexdigest())
 (directory/'results.json').write_text(json.dumps(report,indent=2)+'\n')
 print('DONE automatic URL dependency install',p.returncode,flush=True)
 if p.returncode: print((directory/'install.log').read_text()[-8000:]);raise SystemExit(p.returncode)
 result=subprocess.run(['raco','pkg','show','--all','mcp-syntax-spec-v3','racket-mcp'],cwd=directory,env=env,capture_output=True,text=True,check=True)
 (directory/'installed-packages.log').write_text(result.stdout)
 print(result.stdout,flush=True)
finally:
 server.shutdown();server.server_close();thread.join()
