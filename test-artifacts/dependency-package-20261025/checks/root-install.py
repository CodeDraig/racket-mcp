import pathlib,subprocess,shutil,os,json,time
root=pathlib.Path.cwd();work=root/'.cache/patched-package-20261025';area=work/'root-install';area.mkdir();source=area/'source';source.mkdir()
files=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
for name in filter(None,files):
 p=root/name
 if p.is_file():
  out=source/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,out)
shutil.copytree(root/'packages',source/'packages')
for name in ['test-artifacts/info.rkt','scripts/test-syntax-spec-package.py']:
 out=source/name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,out)
env=dict(os.environ,PLTUSERHOME=str(work/'final-archive-home'),PATH=str(root/'.cache/racket-9.3/bin')+os.pathsep+os.environ['PATH']);env.pop('PLTCOLLECTS',None)
report=[]
for name,cmd in [
 ('install',['raco','pkg','install','--auto','--batch','--no-docs','--copy','--name','racket-mcp',str(source)]),
 ('dependencies',['raco','setup','--check-pkg-deps','--pkgs','racket-mcp','mcp-syntax-spec-v3']),
 ('cli',['raco','mcp','--help'])]:
 print('START root package',name,flush=True);start=time.monotonic()
 with (area/(name+'.log')).open('wb') as log:p=subprocess.run(cmd,cwd=area,env=env,stdout=log,stderr=subprocess.STDOUT)
 report.append(dict(name=name,command=cmd,exit_code=p.returncode,seconds=round(time.monotonic()-start,2)));(area/'results.json').write_text(json.dumps(report,indent=2)+'\n')
 print('DONE root package',name,p.returncode,flush=True)
 if p.returncode:
  print((area/(name+'.log')).read_text()[-8000:]);raise SystemExit(p.returncode)
