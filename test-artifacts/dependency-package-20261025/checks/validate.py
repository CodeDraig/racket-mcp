import os, subprocess, json, pathlib, shutil, time
root=pathlib.Path.cwd()
work=root/'.cache/patched-package-20261025'
source=work/'source'
source.mkdir(exist_ok=False)
files=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
for name in filter(None,files):
 p=root/name
 if p.is_file():
  out=source/name; out.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,out)
shutil.copytree(root/'packages',source/'packages')
env=dict(os.environ,PLTUSERHOME=str(work/'home'),PATH=str(root/'.cache/racket-9.3/bin')+os.pathsep+os.environ['PATH'])
env.pop('PLTCOLLECTS',None)
env['TMPDIR']=str(work/'tmp'); pathlib.Path(env['TMPDIR']).mkdir(exist_ok=True)
report={'steps':[]}
def run(name,cmd,cwd=source):
 print('START',name,flush=True)
 start=time.monotonic()
 with (work/(name+'.log')).open('wb') as log:
  p=subprocess.run(cmd,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT)
 report['steps'].append(dict(name=name,command=cmd,exit_code=p.returncode,seconds=round(time.monotonic()-start,2)))
 (work/'results.json').write_text(json.dumps(report,indent=2)+'\n')
 print('DONE',name,p.returncode,flush=True)
 if p.returncode:
  print((work/(name+'.log')).read_text()[-8000:],flush=True); raise SystemExit(p.returncode)
run('racket-version',['racket','--version'])
run('install-upstream',['raco','pkg','install','--auto','--batch','--no-docs','syntax-spec-v3'])
run('install-patched',['raco','pkg','install','--auto','--batch','--no-docs','--copy','--name','mcp-syntax-spec-v3',str(source/'packages/mcp-syntax-spec-v3')])
run('coexistence',['racket','-e','(require (prefix-in upstream: syntax-spec-v3) (prefix-in patched: mcp-syntax-spec-v3)) (displayln "Both collections load")'])
run('upstream-tests',['raco','test','-p','mcp-syntax-spec-v3'])
run('install-sdk',['raco','pkg','install','--auto','--batch','--no-docs','--copy','--name','racket-mcp',str(source)])
run('cli',['raco','mcp','--help'])
run('focused-tests',['raco','test','tests/phases.rkt','tests/phase-exports.rkt','tests/reference-registration.rkt'])
run('ci',['python3','scripts/ci.py','--skip-bootstrap','--package-home',str(work/'home')])
