import hashlib,os,sys,tempfile,unittest,types
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
import model_store
class DownloadTests(unittest.TestCase):
    def test_repair_bypasses_trusted_cache_for_corruption_with_unchanged_mtime(self):
        payload=b'good';digest=hashlib.sha256(payload).hexdigest()
        lock={role:dict(repo='example/'+role,revision='pinned',files=[dict(name='weights.bin',bytes=4,sha256=digest)]) for role in ('kev','base')}
        calls=[]
        def download(**kwargs):
            calls.append(kwargs)
            # The Hub can trust local metadata/mtime and return stale bytes
            # unless repair explicitly forces a new download.
            path=Path(kwargs['local_dir'])/kwargs['filename']
            if kwargs.get('force_download'):path.write_bytes(payload)
            return str(path)
        fake=types.SimpleNamespace(hf_hub_download=download)
        with tempfile.TemporaryDirectory() as name,patch.dict(sys.modules,{'huggingface_hub':fake}),patch.object(model_store,'manifest',return_value=lock):
            for role in lock:
                path=Path(name)/role/'weights.bin';path.parent.mkdir();path.write_bytes(payload)
            bad=Path(name)/'kev/weights.bin';mtime=bad.stat().st_mtime_ns
            bad.write_bytes(b'bad!');os.utime(bad,ns=(mtime,mtime))
            model_store.download_models(Path(name))
            self.assertEqual(bad.read_bytes(),payload)
        self.assertEqual(len(calls),1,'Valid pinned model files should be reused without network access')
        self.assertIs(calls[0]['force_download'],True)

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
