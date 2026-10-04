import sys,time,unittest,weakref
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
from decision import DecisionService
from server import ModelLoader

class LoaderPrecisionTests(unittest.TestCase):
    def test_reload_releases_previous_ranker_before_allocating_replacement(self):
        old = SimpleRanker()
        old.cycle = old
        reference = weakref.ref(old)
        service = DecisionService(old); del old
        loader = ModelLoader(service, Path('/unused'))
        released = []
        def replacement(*args):
            released.append(reference() is None)
            return SimpleRanker()
        with patch('kev_ranker.KevRanker', side_effect=replacement):
            loader.start(); self.wait_loaded(loader)
        self.assertEqual(released, [True], 'Reload must not allocate two backbones together')
        self.assertEqual(loader.status, 'ready')
    def wait_loaded(self,loader):
        deadline=time.monotonic()+2
        while loader.status=='loading':
            self.assertLess(time.monotonic(),deadline,'Loader never finished')
            time.sleep(.005)
    def test_ready_health_identifies_the_installed_model_precision(self):
        info=dict(quantization='mxfp8',backbone_weight_bytes=776393408,unquantized_backbone_weight_bytes=1504791232)
        service=DecisionService();loader=ModelLoader(service,Path('/unused'))
        # Replace only loading the large checkpoint, not the loader/service.
        with patch('kev_ranker.KevRanker',return_value=SimpleNamespace(model_info=info)):
            loader.start();self.wait_loaded(loader)
        self.assertEqual(loader.status,'ready')
        self.assertEqual(loader.health().get('quantization'),'mxfp8')
        self.assertEqual(loader.health().get('backbone_weight_bytes'),776393408)
        self.assertEqual(service.ranker.model_info,info)
        loader.status='loading'
        self.assertNotIn('quantization',loader.health())
        loader.status='error'
        self.assertNotIn('backbone_weight_bytes',loader.health())

class SimpleRanker:
    model_info = {}

if __name__=='__main__':unittest.main()
