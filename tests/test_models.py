import hashlib,json,os,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
from model_store import data_dir,validate_models

class ModelStoreTests(unittest.TestCase):
    def test_portable_data_path_can_be_overridden_without_build_checkout(self):
        with patch.dict(os.environ,{'TELEPATHY_DATA_DIR':'/tmp/telepathy arbitrary location'}):
            self.assertEqual(data_dir(),Path('/tmp/telepathy arbitrary location'))
    def test_missing_or_modified_checkpoint_is_rejected_before_model_loading(self):
        payload=b'pinned model fixture'
        manifest={k:dict(files=[dict(name='weights.bin',bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest())]) for k in ('kev','base')}
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(FileNotFoundError): validate_models(d,manifest)
            for role in ('kev','base'):
                p=Path(d)/role;p.mkdir();(p/'weights.bin').write_bytes(payload)
            self.assertEqual(validate_models(d,manifest)['kev'],Path(d)/'kev')
            (Path(d)/'base/weights.bin').write_bytes(b'changed')
            with self.assertRaises(ValueError): validate_models(d,manifest)
    def test_manifest_has_no_training_artifacts_or_private_paths(self):
        manifest=json.loads((Path(__file__).resolve().parents[1]/'assets/models.lock.json').read_text())
        self.assertNotIn('checkpoint',manifest['kev'])
        self.assertEqual({f['name'] for f in manifest['kev']['files']},{'adapter_config.json','adapter_model.safetensors','head.pt'})

if __name__=='__main__': unittest.main()
