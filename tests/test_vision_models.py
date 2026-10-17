import fcntl
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
import weakref
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'worker'))
import model_store


class VisionModelStoreTests(unittest.TestCase):
    def test_default_manifest_is_exactly_one_pinned_vision_checkpoint(self):
        lock = model_store.manifest()
        candidate = json.loads((ROOT / 'experiments/screen-language/single-model-results.json').read_text())['candidate']
        self.assertEqual(set(lock), {'vision'})
        self.assertEqual(lock['vision'], candidate)

    def test_validation_and_download_accept_single_vision_role(self):
        payload = b'verified vision checkpoint'
        lock = {'vision': dict(repo='example/vision', revision='pinned', files=[dict(name='weights.bin',
            bytes=len(payload), sha256=hashlib.sha256(payload).hexdigest())])}
        requests = []
        def download(**kwargs):
            requests.append(kwargs)
            target = Path(kwargs['local_dir']) / kwargs['filename']
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload)
        with tempfile.TemporaryDirectory() as root, patch.object(model_store, 'manifest', return_value=lock), \
             patch.dict(sys.modules, {'huggingface_hub': types.SimpleNamespace(hf_hub_download=download)}):
            model_store.download_models(root)
            self.assertEqual(model_store.validate_models(root, lock), {'vision': Path(root) / 'vision'})
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0]['repo_id'], 'example/vision')
        self.assertIs(requests[0]['token'], False)


class VisionCommandTests(unittest.TestCase):
    def test_self_test_uses_only_default_vision_backend(self):
        import contextlib
        from io import StringIO
        import main
        calls = []
        class Ranker:
            def __init__(self, root):
                calls.append(root)
            def rank(self, *args, **kwargs):
                self.assertion = kwargs
                return dict(order=[1, 0], ranker='continuation')
        output = StringIO()
        with tempfile.TemporaryDirectory() as root, \
             patch.dict(sys.modules, {'vision_ranker': types.SimpleNamespace(VisionRanker=Ranker), 'kev_ranker': None}), \
             patch.object(main, 'data_dir', return_value=Path(root)), \
             patch.object(sys, 'argv', ['Telepathy', '--self-test', '--model-dir', '/fixture/models']), \
             contextlib.redirect_stdout(output):
            main.main()
        self.assertEqual(calls, [Path('/fixture/models')])
        self.assertEqual(json.loads(output.getvalue())['ranker'], 'continuation')

    def test_self_test_releases_model_cycles_before_unlocking(self):
        import contextlib
        from io import StringIO
        import main
        references, released_while_locked = [], []
        with tempfile.TemporaryDirectory() as root:
            class Ranker:
                def __init__(self, model_root):
                    self.cycle = self
                    references.append(weakref.ref(self))
                def rank(self, *args, **kwargs):
                    return dict(order=[1, 0])
                def __del__(self):
                    with (Path(root) / '.worker.lock').open('w') as probe:
                        try:
                            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                            released_while_locked.append(False)
                        except BlockingIOError:
                            released_while_locked.append(True)
            with patch.dict(sys.modules, {'vision_ranker': types.SimpleNamespace(VisionRanker=Ranker)}), \
                 patch.object(main, 'data_dir', return_value=Path(root)), \
                 patch.object(sys, 'argv', ['Telepathy', '--self-test']), \
                 contextlib.redirect_stdout(StringIO()):
                main.main()
            self.assertIsNone(references[0](), 'Self-test must release model cycles inside singleton lock')
            self.assertEqual(released_while_locked, [True])

    def test_failed_self_test_releases_model_before_unlocking(self):
        import main
        references, released_while_locked = [], []
        with tempfile.TemporaryDirectory() as root, (Path(root) / '.worker.lock').open('w') as probe:
            class Ranker:
                def __init__(self, model_root):
                    self.cycle = self
                    references.append(weakref.ref(self))
                def rank(self, *args, **kwargs):
                    raise RuntimeError('inference failed')
                def __del__(self):
                    try:
                        fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        released_while_locked.append(False)
                    except BlockingIOError:
                        released_while_locked.append(True)
            with patch.dict(sys.modules, {'vision_ranker': types.SimpleNamespace(VisionRanker=Ranker)}), \
                 patch.object(main, 'data_dir', return_value=Path(root)), \
                 patch.object(sys, 'argv', ['Telepathy', '--self-test']):
                with self.assertRaises(SystemExit):
                    main.main()
            self.assertIsNone(references[0]())
            self.assertEqual(released_while_locked, [True])
            fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_self_test_cannot_load_a_second_resident_model(self):
        import main
        calls = []
        fake = types.SimpleNamespace(VisionRanker=lambda root: calls.append(root))
        with tempfile.TemporaryDirectory() as root, (Path(root) / '.worker.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.dict(sys.modules, {'vision_ranker': fake}), \
                 patch.object(main, 'data_dir', return_value=Path(root)), \
                 patch.object(sys, 'argv', ['Telepathy', '--self-test', '--model-dir', '/fixture/models']):
                with self.assertRaises(SystemExit) as stopped:
                    main.main()
            self.assertIn('already running', str(stopped.exception))
            self.assertEqual(calls, [], 'A self-test must fail before allocating a second checkpoint')


if __name__ == '__main__':
    unittest.main()
