import pathlib, subprocess, json, os, hashlib
root=pathlib.Path.cwd()
out=root/'test-artifacts/oauth-all-scenarios-20260908/corrected-fixture'
harness=root/'.cache/conformance-oauth-registration-20260908'
env=os.environ.copy()
env.update(PLTUSERHOME=str(root/'.racket'),PLTCOLLECTS=str(root)+':',TMPDIR=str(root/'.cache/tmp'))
scenarios=json.loads((out/'scenarios.json').read_text())
commands=[]; exits={}
for scenario in scenarios:
 argv=[str(harness/'node_modules/.bin/tsx'),str(harness/'src/index.ts'),'client','--command','/usr/bin/racket '+str(root/'dev/conformance-auth-client.rkt'),'--scenario',scenario,'--spec-version','2026-07-28','--timeout','60000','--output-dir',str(out/'results')]
 commands.append(argv); (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 with (out/(scenario.replace('/','-')+'.log')).open('w') as log:
  result=subprocess.run(argv,cwd=harness,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=100)
 exits[scenario]=result.returncode
 (out/'exits.json').write_text(json.dumps(exits,indent=2)+'\n')
 print(scenario, result.returncode, flush=True)
