import hashlib,sys,tempfile,unittest,types
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
import model_store
class DownloadTests(unittest.TestCase):
    def test_only_pinned_required_files_are_requested_without_credentials(self):
        payload=b'fixture';digest=hashlib.sha256(payload).hexdigest()
        lock={role:dict(repo='example/'+role,revision='pinned-revision',files=[dict(name='required.bin',bytes=len(payload),sha256=digest)]) for role in ('kev','base')}
        calls=[]
        def download(**kwargs):
            calls.append(kwargs);path=Path(kwargs['local_dir']);path.mkdir(parents=True,exist_ok=True);(path/kwargs['filename']).write_bytes(payload)
        fake=types.SimpleNamespace(hf_hub_download=download)
        with tempfile.TemporaryDirectory() as name,patch.dict(sys.modules,{'huggingface_hub':fake}),patch.object(model_store,'manifest',return_value=lock):
            model_store.download_models(Path(name))
        self.assertEqual(len(calls),2)
        for call in calls:
            self.assertEqual(call['revision'],'pinned-revision');self.assertEqual(call['filename'],'required.bin');self.assertIs(call['token'],False)
