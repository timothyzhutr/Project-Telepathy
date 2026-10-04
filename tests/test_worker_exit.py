import fcntl,json,os,socket,subprocess,sys,tempfile,time,unittest,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class WorkerExitTests(unittest.TestCase):
    def test_waiting_restart_acquires_lock_then_shutdown_releases_process(self):
        with tempfile.TemporaryDirectory(prefix='telepathy worker lifecycle ') as name:
            root=Path(name)
            with socket.socket() as sock:
                sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
            with (root/'.worker.lock').open('w') as lock:
                fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                process=subprocess.Popen([sys.executable,str(ROOT/'worker/main.py'),'--serve','--wait-lock',
                    '--port',str(port),'--model-dir',str(root/'missing')],
                    env=dict(os.environ,TELEPATHY_DATA_DIR=name),stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                try:
                    time.sleep(.2)
                    self.assertIsNone(process.poll(),'Restart should wait for the prior helper to release its lock')
                    fcntl.flock(lock,fcntl.LOCK_UN)
                    deadline=time.monotonic()+5
                    url='http://127.0.0.1:'+str(port)
                    while True:
                        try:
                            with urllib.request.urlopen(url+'/api/health',timeout=.2) as response:health=json.load(response)
                            if health['status']=='model_missing':break
                        except OSError:pass
                        self.assertLess(time.monotonic(),deadline,'Restarted worker never became available')
                        time.sleep(.02)
                    with urllib.request.urlopen(urllib.request.Request(url+'/api/shutdown',data=b'{}'),timeout=2) as response:
                        self.assertEqual(json.load(response)['status'],'stopping')
                    self.assertEqual(process.wait(timeout=5),0)
                    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                finally:
                    if process.poll() is None:process.terminate();process.wait(timeout=5)

if __name__=='__main__':unittest.main()
