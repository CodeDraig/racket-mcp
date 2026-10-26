import os,subprocess,json,pathlib,time,zipfile
root=pathlib.Path.cwd(); work=root/'.cache/patched-package-20261025'; logdir=work/'racket-9.2-ci'; logdir.mkdir()
with zipfile.ZipFile(work/'archive-install/racket-mcp.zip') as z: z.extractall(logdir/'source')
source=logdir/'source/racket-mcp'
env=dict(os.environ,PATH=str(root/'.cache/public-readiness-20261025/tools/racket-9.2/bin')+os.pathsep+os.environ['PATH']);env.pop('PLTCOLLECTS',None)
cmd=['python3','scripts/ci.py','--skip-bootstrap','--package-home',str(work/'racket-9.2-retry/home')]
start=time.monotonic()
with (logdir/'ci.log').open('wb') as log:
 p=subprocess.run(cmd,cwd=source,env=env,stdout=log,stderr=subprocess.STDOUT)
(logdir/'results.json').write_text(json.dumps(dict(command=cmd,exit_code=p.returncode,seconds=round(time.monotonic()-start,2)),indent=2)+'\n')
print('9.2 normal CI exit:',p.returncode,flush=True)
if p.returncode: print((logdir/'ci.log').read_text()[-8000:])
raise SystemExit(p.returncode)
