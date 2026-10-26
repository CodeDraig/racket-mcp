from pathlib import Path
import shutil,hashlib,json,subprocess
root=Path.cwd(); work=root/'.cache/patched-package-20261025'; out=root/'test-artifacts/dependency-package-20261025'
out.mkdir(exist_ok=True)
def copy(source,target):
 target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
for path in work.iterdir():
 if path.is_file() and path.suffix in ('.json','.log','.py'):
  copy(path,out/'checks'/path.name)
for label,base in [('racket-9.3',work/'source/.cache/ci/results'),('racket-9.2',work/'racket-9.2-ci/source/racket-mcp/.cache/ci/results')]:
 for path in base.glob('*'):
  if path.is_file():copy(path,out/label/path.name)
for name in ['racket-9.2','racket-9.2-retry','auto-install','root-install']:
 for path in (work/name).iterdir():
  if path.is_file() and path.suffix in ('.json','.log'):copy(path,out/'checks'/name/path.name)
# Record source bytes, not generated compilation files. Historical receipts are
# excluded to avoid recursively hashing this evidence directory.
inputs={}
for folder in ['mcp','tests','dev','scripts','packages']:
 for path in (root/folder).rglob('*'):
  if path.is_file() and not any(part in ('compiled','__pycache__','node_modules','doc') for part in path.relative_to(root).parts):
   inputs[path.relative_to(root).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
for name in ['info.rkt','README.md','THIRD-PARTY-NOTICES.md','vendor/LOCK.json','test-artifacts/info.rkt']:
 inputs[name]=hashlib.sha256((root/name).read_bytes()).hexdigest()
(out/'inputs.json').write_text(json.dumps({'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'sha256':dict(sorted(inputs.items()))},indent=2)+'\n')
files=sorted(path for path in out.rglob('*') if path.is_file() and path.name!='SHA256SUMS')
(out/'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(out).as_posix()+'\n' for p in files))
print('Saved',len(files),'evidence files')
