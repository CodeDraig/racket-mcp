import pathlib, subprocess, json
root=pathlib.Path('/srv/data/code/racket-mcp/.cache/public-readiness-20261025/racket-9.3-corrected')
out=pathlib.Path('/srv/data/code/racket-mcp/.cache/public-readiness-20261025/conformance-retry/clients')
harness=pathlib.Path('/srv/data/code/racket-mcp/.cache/conformance-pinned')
scenarios=['tools_call','request-metadata','sep-2322-client-request-state','http-standard-headers','http-custom-headers','http-invalid-tool-headers','json-schema-ref-no-deref','json-schema-2020-12-preservation','auth/basic-cimd','auth/pre-registration','auth/resource-mismatch','auth/metadata-issuer-mismatch']
commands=[]
exits={}
for scenario in scenarios:
 fixture='conformance-auth-client.rkt' if scenario.startswith('auth/') else 'conformance-client.rkt'
 argv=[str(harness/'node_modules/.bin/tsx'),str(harness/'src/index.ts'),'client','--command','/srv/data/code/racket-mcp/.cache/racket-9.3/bin/racket'+' '+str(root/'dev'/fixture),'--scenario',scenario,'--spec-version','2026-07-28','--timeout','60000','--output-dir',str(out/'results')]
 commands.append(argv)
 (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 with (out/(scenario.replace('/','-')+'.log')).open('w') as log:
  result=subprocess.run(argv,cwd=harness,stdout=log,stderr=subprocess.STDOUT)
 exits[scenario]=result.returncode
 (out/'exits.json').write_text(json.dumps(exits,indent=2)+'\n')
