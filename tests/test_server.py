import sys,unittest,json,threading,urllib.request,urllib.error
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
from decision import DecisionService
from server import make_server
class ServerTests(unittest.TestCase):
    def setUp(self):
        self.server=make_server(0,DecisionService());threading.Thread(target=self.server.serve_forever,daemon=True).start()
        self.url='http://127.0.0.1:'+str(self.server.server_port)
    def tearDown(self): self.server.shutdown();self.server.server_close()
    def request(self,path,data=None,headers=None):
        req=urllib.request.Request(self.url+path,data=data,headers=headers or {})
        try:
            with urllib.request.urlopen(req) as r: return r.status,json.load(r)
        except urllib.error.HTTPError as r: return r.code,json.load(r)
    def test_health_and_fallback(self):
        status,body=self.request('/api/health');self.assertEqual((status,body['app']),(200,'Telepathy'))
        snapshot=dict(revision=1,prefix='我申请了',pinyin='quanli',candidates=['权力','权利'],candidate_ends=[6,6])
        status,body=self.request('/api/decision',json.dumps(snapshot).encode())
        self.assertEqual((status,body['status'],body['order']),(200,'unavailable',[0,1]))
    def test_foreign_origins_and_hosts_rejected(self):
        for headers in ({'Origin':'https://evil.example'},{'Host':'evil.example'}):
            self.assertEqual(self.request('/api/health',headers=headers)[0],403)
    def test_bad_payload_and_unknown_endpoint(self):
        self.assertEqual(self.request('/api/decision',b'{}')[0],400)
        self.assertEqual(self.request('/api/decision',b'x'*8193)[0],413)
        self.assertEqual(self.request('/compose',b'{}')[0],404)
