from pathlib import Path
import tempfile
root=Path.cwd()
folder=Path(tempfile.mkdtemp(prefix='mcp-embedded-bootstrap-',dir=root/'.cache/tmp'))
source=(root/'dev/command-observation-server.rkt').read_text()
kernel=(root/'mcp/private/kernel-observation.rkt').read_text().strip()
body=kernel[kernel.index('\n')+1:-1]
body=body.replace('  (#%provide call-with-kernel-observation install-kernel-observation!)\n','')
prior=Path('/tmp/mcp-current-handoff-server.rkt').read_text()
extra=prior[prior.index('  (define-values (parent)',prior.index('(module configure-runtime')):]
# extra already closes the configure-runtime module.
app=folder/'application.rkt'
app.write_text(source+'\n(module configure-runtime \'#%kernel\n'+body+'\n'+extra)
probe=Path('/tmp/mcp-current-handoff-probe.rkt').read_text().replace('/tmp/mcp-current-handoff-server.rkt',str(app))
(folder/'probe.rkt').write_text(probe)
print(folder)
Path('/tmp/mcp-embedded-bootstrap-location').write_text(str(folder))
