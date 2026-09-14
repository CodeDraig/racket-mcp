from pathlib import Path
import json, collections, hashlib, difflib
out=Path('test-artifacts/oauth-all-scenarios-20260908'); scenarios=json.loads((out/'scenarios.json').read_text()); summary={}
for name,where in [('unmodified',out),('registration_fixture_corrected',out/'corrected-fixture')]:
 rows=[]
 for scenario in scenarios:
  paths=list((where/'results'/Path(scenario).parent).glob(Path(scenario).name+'-20??-*/checks.json'))
  assert len(paths)==1,(scenario,paths)
  checks=json.loads(paths[0].read_text());counts=dict(collections.Counter(c['status'] for c in checks))
  rows.append(dict(scenario=scenario,exit=json.loads((where/'exits.json').read_text())[scenario],counts=counts,
                   scored_pass=counts.get('SUCCESS',0)>0 and counts.get('FAILURE',0)==0,
                   issues=[dict(id=c['id'],status=c['status'],description=c.get('description')) for c in checks if c['status'] in ['FAILURE','WARNING']]))
 summary[name]=rows
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
files=['dev/conformance-auth-client.rkt','mcp/oauth.rkt','mcp/oauth-registration.rkt','mcp/oauth-registration-store.rkt','mcp/authorization.rkt']
(out/'sdk-source-sha256.json').write_text(json.dumps({f:hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in files},indent=2)+'\n')
base=Path('/tmp/racket-mcp-conformance-elicitation-20260907');vendor=Path('vendor/conformance');patch=[]
for p in (base/'src').rglob('*'):
 if p.is_file():
  rel=p.relative_to(base);v=vendor/rel
  if v.exists() and v.read_bytes()!=p.read_bytes():
   patch.extend(difflib.unified_diff(v.read_text().splitlines(True),p.read_text().splitlines(True),fromfile='a/'+str(rel),tofile='b/'+str(rel)))
(out/'existing-harness-overlay.patch').write_text(''.join(patch))
print('existing overlay lines',len(patch))
for name,rows in summary.items(): print(name,len(rows),'scored passes',sum(r['scored_pass'] for r in rows))
