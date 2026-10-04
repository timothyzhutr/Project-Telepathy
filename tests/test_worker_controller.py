import socket,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

@unittest.skipUnless(sys.platform=='darwin','Native macOS helper lifecycle')
class WorkerControllerTests(unittest.TestCase):
    def test_preferences_drive_actual_helper_process(self):
        with tempfile.TemporaryDirectory(prefix='telepathy native worker ') as name:
            executable=Path(name)/'worker-controller-tests'
            sources=[ROOT/'native/Sources/TelepathyPreferences.swift',ROOT/'native/Sources/TelepathyWorkerController.swift',ROOT/'native/Tests/WorkerControllerTests.swift']
            result=subprocess.run(['xcrun','swiftc','-swift-version','5',*[str(p) for p in sources if p.exists()],'-o',str(executable)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,'Worker lifecycle test could not compile:\n'+result.stderr)
            with socket.socket() as sock:
                sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
            result=subprocess.run([str(executable),sys.executable,str(ROOT/'worker/main.py'),name,str(port)],capture_output=True,text=True,timeout=25)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('PASS: real helper',result.stdout)

if __name__=='__main__':unittest.main()
