import hashlib,http.server,json,os,pathlib,ssl,subprocess,tempfile,threading
root=pathlib.Path.cwd()
out=root/'test-artifacts/final-offline-access-20260908'
harness=pathlib.Path('/tmp/racket-mcp-conformance-elicitation-20260907')
files=list((root/'vendor/conformance/src').rglob('*'))
inputs=[]
for p in files:
 if p.is_file():
  rel=p.relative_to(root/'vendor/conformance')
  digest=hashlib.sha256(p.read_bytes()).hexdigest()
  assert digest==hashlib.sha256((harness/rel).read_bytes()).hexdigest(),str(rel)
  inputs.append({'file':str(rel),'sha256':digest})
(out/'harness-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
with tempfile.TemporaryDirectory(prefix='mcp-cimd-tls-') as temporary:
 directory=pathlib.Path(temporary); key=directory/'key.pem'; cert=directory/'cert.pem'
 subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=127.0.0.1','-addext','subjectAltName=IP:127.0.0.1'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 requests=[]; metadata=b''
 class Handler(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
   requests.append(self.path)
   if self.path!='/client-metadata.json': self.send_error(404); return
   self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(metadata))); self.end_headers(); self.wfile.write(metadata)
  def log_message(self,*args): pass
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
 context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert,key)
 server.socket=context.wrap_socket(server.socket,server_side=True)
 url=f'https://127.0.0.1:{server.server_port}/client-metadata.json'
 env=os.environ.copy(); env['MCP_CONFORMANCE_CLIENT_METADATA_URL']=url; env['NODE_EXTRA_CA_CERTS']=str(cert)
 expression='(begin (require mcp/authorization mcp/json) (write-json (client-id-metadata-document (getenv "MCP_CONFORMANCE_CLIENT_METADATA_URL") "Racket MCP conformance" (list "http://localhost:3080/callback"))))'
 metadata=subprocess.check_output(['racket','-e',expression],env=env)
 (out/'client-metadata.json').write_bytes(metadata+b'\n')
 worker=threading.Thread(target=server.serve_forever,daemon=True); worker.start()
 argv=[str(harness/'node_modules/.bin/tsx'),str(harness/'src/index.ts'),'client','--command',str(root/'.cache/racket-9.3/bin/racket')+' '+str(root/'dev/conformance-auth-client.rkt'),'--scenario','auth/offline-access-scope','--spec-version','2026-07-28','--timeout','60000','--output-dir',str(out/'results')]
 (out/'commands.json').write_text(json.dumps({'harness':argv,'metadataUrl':url,'trust':'temporary self-signed local certificate via NODE_EXTRA_CA_CERTS; no TLS verification disabled'},indent=2)+'\n')
 try:
  with (out/'harness.log').open('w') as log: result=subprocess.run(argv,cwd=harness,env=env,stdout=log,stderr=subprocess.STDOUT)
  (out/'exit.json').write_text(json.dumps({'harness':result.returncode})+'\n')
 finally:
  server.shutdown(); server.server_close(); worker.join()
  (out/'metadata-requests.json').write_text(json.dumps(requests)+'\n')
