import subprocess,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

class NativeResilienceTests(unittest.TestCase):
    def test_context_profile_and_transport_contracts(self):
        with tempfile.TemporaryDirectory(prefix='telepathy resilience ') as name:
            binary=Path(name)/'resilience'
            sources=[ROOT/'native/Sources'/file for file in ('DecisionSnapshot.swift','ProfileSeeder.swift','DecisionTransport.swift','TelepathyWorkerController.swift','TelepathyPreferences.swift')]
            result=subprocess.run(['xcrun','swiftc','-swift-version','5',*[str(p) for p in sources if p.exists()],str(ROOT/'native/Tests/ResilienceTests.swift'),'-o',str(binary)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            result=subprocess.run([str(binary)],capture_output=True,text=True,timeout=10)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
