import fcntl,os,signal,socket,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform=='darwin','Native macOS helper lifecycle')
class WorkerControllerTests(unittest.TestCase):
    def test_preferences_drive_actual_helper_process(self):
        self.run_controller(False)
    def test_lock_contention_clean_exit_does_not_respawn(self):
        self.run_controller(True)
    def test_abnormal_exit_retries_and_assistance_off_cancels_retry(self):
        self.run_controller(False, crash=True)
    def run_controller(self, contention, crash=False):
        with tempfile.TemporaryDirectory(prefix='telepathy native worker ') as name:
            executable=Path(name)/'worker-controller-tests'
            sources=[ROOT/'native/Sources/TelepathyPreferences.swift',ROOT/'native/Sources/TelepathyWorkerController.swift',ROOT/'native/Tests/WorkerControllerTests.swift']
            result=subprocess.run(['xcrun','swiftc','-swift-version','5',*[str(p) for p in sources if p.exists()],'-o',str(executable)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,'Worker lifecycle test could not compile:\n'+result.stderr)
            with socket.socket() as sock:
                sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
            with (Path(name)/'.worker.lock').open('w') as lock:
                if contention: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                args=[str(executable),sys.executable,str(ROOT/'worker/main.py'),name,str(port)]
                if contention:args.append('--lock-contention')
                if crash:args.append('--crash-retry')
                process=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
                try:
                    stdout,stderr=process.communicate(timeout=35)
                    self.assertEqual(process.returncode,0,stdout+stderr)
                    self.assertIn('PASS:',stdout)
                finally:
                    # Failed native preconditions do not run Swift defer blocks.
                    # Kill only the isolated test process group, including children.
                    try:os.killpg(process.pid,signal.SIGTERM)
                    except ProcessLookupError:pass
                    process.wait(timeout=5)

if __name__=='__main__':unittest.main()
