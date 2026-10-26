import os,subprocess,json,pathlib,time
root=pathlib.Path.cwd(); work=root/'.cache/patched-package-20261025'
env=dict(os.environ,PLTUSERHOME=str(work/'final-archive-home'),PATH=str(root/'.cache/racket-9.3/bin')+os.pathsep+os.environ['PATH']); env.pop('PLTCOLLECTS',None)
steps=[]
for name,cmd in [
 ('final-archive-install',['raco','pkg','install','--auto','--batch','--no-docs',str(work/'mcp-syntax-spec-v3.zip')]),
 ('final-archive-load',['racket','-e','(require mcp-syntax-spec-v3 (for-meta 1 racket/base mcp-syntax-spec-v3) (for-meta 2 racket/base mcp-syntax-spec-v3)) (displayln "Patched collection loads at phases 0, 1, 2")']),
 ('final-archive-dependencies',['raco','setup','--check-pkg-deps','--pkgs','mcp-syntax-spec-v3'])]:
 print('START',name,flush=True); start=time.monotonic()
 with (work/(name+'.log')).open('wb') as log:
  p=subprocess.run(cmd,cwd=work,env=env,stdout=log,stderr=subprocess.STDOUT)
 steps.append(dict(name=name,command=cmd,exit_code=p.returncode,seconds=round(time.monotonic()-start,2)))
 (work/'final-archive-results.json').write_text(json.dumps(steps,indent=2)+'\n')
 print('DONE',name,p.returncode,flush=True)
 if p.returncode:
  print((work/(name+'.log')).read_text()[-5000:],flush=True);raise SystemExit(p.returncode)
