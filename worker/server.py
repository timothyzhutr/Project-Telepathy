"""Loopback-only native ranking service. No text/request logging."""
import json,threading
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer

def make_server(port,service,health=None,reload_model=None):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def setup(self):
            super().setup();self.connection.settimeout(4)
        def send(self,status,body):
            data=json.dumps(body,ensure_ascii=False).encode()
            self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def allowed(self):
            expected='127.0.0.1:'+str(self.server.server_port)
            if self.headers.get('Host')!=expected or self.headers.get('Origin') not in (None,'http://'+expected):
                self.send(403,{'error':'Local native clients only'});return False
            return True
        def do_GET(self):
            if not self.allowed(): return
            if self.path!='/api/health': self.send(404,{'error':'Unknown endpoint'});return
            self.send(200,dict(app='Telepathy',version='0.1.3',ime_api=1,local=True,engine='Kev/MLX',**(health() if health else {'status':'model_missing'})))
        def do_POST(self):
            if not self.allowed(): return
            if self.path not in ('/api/decision','/api/reload'): self.send(404,{'error':'Unknown endpoint'});return
            try:
                length=int(self.headers.get('Content-Length','-1'))
                if not 0<=length<=8192:
                    self.send(413,{'error':'Body too large or missing length'});return
                body=json.loads(self.rfile.read(length))
                if self.path=='/api/reload':
                    if reload_model: reload_model()
                    self.send(202,{'status':'loading'});return
                self.send(200,service.decision(body))
            except (ValueError,UnicodeError): self.send(400,{'error':'Invalid snapshot'})
    server=ThreadingHTTPServer(('127.0.0.1',port),Handler);server.daemon_threads=True
    return server

class ModelLoader:
    def __init__(self,service,model_dir):
        self.service,self.model_dir=service,model_dir
        self.status='model_missing';self.error=None;self.lock=threading.Lock()
    def health(self): return dict(status=self.status,error=self.error)
    def start(self):
        if not self.lock.acquire(blocking=False): return
        def load():
            self.status='loading';self.error=None
            try:
                from kev_ranker import KevRanker
                ranker=KevRanker(self.model_dir)
                with self.service.lock: self.service.ranker=ranker
                self.status='ready'
            except FileNotFoundError:
                self.status='model_missing';self.error='Run Telepathy --download-model.'
            except Exception as error:
                self.status='error';self.error=type(error).__name__+'; run --check-model or inspect the worker log.'
                # Log the exception type, never the user's text or local paths.
                print('Model initialization failed: '+type(error).__name__,flush=True)
            finally: self.lock.release()
        threading.Thread(target=load,daemon=True).start()
