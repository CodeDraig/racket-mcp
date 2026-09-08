"""Compare two clean distributions after final ledger/documentation updates."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parents[2]
output = Path(__file__).resolve().parent
archive = root / '.cache/distribution/racket-mcp-0.1.zip'
with tempfile.TemporaryDirectory(prefix='mcp-release-archives-') as directory:
    first = Path(directory) / 'first.zip'
    with (output / 'archive-build.log').open('w') as log:
        subprocess.run([sys.executable, 'scripts/package.py'], cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
        first.write_bytes(archive.read_bytes())
        subprocess.run([sys.executable, 'scripts/package.py'], cwd=root, stdout=log, stderr=subprocess.STDOUT, check=True)
    assert first.read_bytes() == archive.read_bytes(), 'source archives differ'
    with zipfile.ZipFile(archive) as source:
        names = source.namelist()
        assert 'racket-mcp/REMAINING.md' in names
        assert 'racket-mcp/mcp/build.rkt' in names
        assert not any(set(Path(name).parts) & {'compiled', '.cache', '.racket', 'node_modules', '.git', 'test-artifacts'} for name in names)
        assert source.testzip() is None
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    result = {'identical': True, 'sha256': digest, 'bytes': archive.stat().st_size,
              'files': len(names), 'archive': str(archive.relative_to(root)),
              'sdk_commit': subprocess.check_output(['git', 'log', '-1', '--format=%H', '--', 'mcp'], cwd=root, text=True).strip()}
    (output / 'reproducibility.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
