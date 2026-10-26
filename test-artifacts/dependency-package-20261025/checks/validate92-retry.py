import os, subprocess, json, pathlib, time, zipfile
root=pathlib.Path.cwd(); work=root/'.cache/patched-package-20261025'; source=work/'source'
logs=work/'racket-9.2-retry'; logs.mkdir(exist_ok=False)
with zipfile.ZipFile(work/'archive-install/racket-mcp.zip') as z: z.extractall(logs/'source')
source=logs/'source/racket-mcp'
env=dict(os.environ,PLTUSERHOME=str(logs/'home'),PATH=str(root/'.cache/public-readiness-20261025/tools/racket-9.2/bin')+os.pathsep+os.environ['PATH'])
env.pop('PLTCOLLECTS',None); env['TMPDIR']=str(logs/'tmp'); pathlib.Path(env['TMPDIR']).mkdir()
report={'steps':[]}
def run(name,cmd):
 print('START',name,flush=True); start=time.monotonic()
 with (logs/(name+'.log')).open('wb') as f: p=subprocess.run(cmd,cwd=source,env=env,stdout=f,stderr=subprocess.STDOUT)
 report['steps'].append(dict(name=name,command=cmd,exit_code=p.returncode,seconds=round(time.monotonic()-start,2)))
 (logs/'results.json').write_text(json.dumps(report,indent=2)+'\n'); print('DONE',name,p.returncode,flush=True)
 if p.returncode:
  print((logs/(name+'.log')).read_text()[-8000:],flush=True); raise SystemExit(p.returncode)
run('racket-version',['racket','--version'])
archives=work/'archive-install'
run('install-archives',['raco','pkg','install','--auto','--batch','--no-docs',str(archives/'mcp-syntax-spec-v3.zip'),str(archives/'racket-mcp.zip')])
run('cli',['raco','mcp','--help'])
run('focused-tests',['raco','test','tests/phases.rkt','tests/phase-exports.rkt','tests/reference-registration.rkt'])
run('native-tests',['raco','test','tests'])
run('package-dependencies',['raco','setup','--check-pkg-deps','--pkgs','mcp-syntax-spec-v3','racket-mcp'])
