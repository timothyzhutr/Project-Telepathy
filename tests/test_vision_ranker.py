"""Shared text/vision weights and state isolation without loading a checkpoint."""
import importlib.util
import math
from contextlib import nullcontext
from pathlib import Path
import sys
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))


class Cache:
    def __init__(self, state=0):
        self.state = state

    @classmethod
    def merge(cls, entries):
        return cls(entries[0].state)


class TextModel:
    def __call__(self, ids, cache=None):
        if cache:
            cache[0].state += ids.shape[-1]
        return np.stack([ids % 3, (ids + 1) % 5], axis=-1).astype(np.float32)


class Tokenizer:
    pad_token_id = 0
    all_special_ids = [15]
    def __call__(self, value, **kwargs):
        return SimpleNamespace(input_ids=[1 + ord(c) % 13 for c in value],
                               offset_mapping=[(i, i + 1) for i in range(len(value))])
    def encode(self, label, **kwargs):
        return [[2], [5]][label == 'B']


class Model:
    def __init__(self):
        self.image_caches = []
        self.language_model = SimpleNamespace(model=TextModel(), make_cache=lambda: [Cache()], lm_head=self.head)
        self.config = SimpleNamespace(image_token_index=99)
        self.rope_metadata = None
    def parameters(self):
        return {'weights': np.zeros(32, dtype=np.uint8)}
    def __call__(self, ids, pixels, *, mask, cache, **kwargs):
        self.image_caches.append(cache)
        cache[0].state = 999
        self.rope_metadata = 'image positions retained by multimodal wrapper'
        return SimpleNamespace(hidden_states=[np.array([[[.1, .8]]], dtype=np.float32)])
    @staticmethod
    def head(hidden):
        return hidden[..., :1] * np.arange(16) + hidden[..., 1:2] * np.arange(16)[::-1]


class Processor:
    tokenizer = Tokenizer()
    def __init__(self):
        self.messages = []
    def apply_chat_template(self, messages, **kwargs):
        self.messages.append((messages, kwargs))
        return 'test image prompt'


class VisionRankerTests(unittest.TestCase):
    def ranker_type(self):
        self.assertIsNotNone(importlib.util.find_spec('vision_ranker'), 'Production VisionRanker is missing')
        from vision_ranker import VisionRanker
        return VisionRanker

    def setup_ranker(self):
        cls = self.ranker_type()
        model, processor = Model(), Processor()
        calls, prepared = [], []
        def load(*args, **kwargs):
            calls.append((args, kwargs))
            return model, processor
        def prepare_inputs(processor, *, images, prompts, image_token_index):
            prepared.append(images)
            return dict(input_ids=np.array([[1, 2]]), pixel_values=np.zeros((1, 2)), attention_mask=np.ones((1, 2)))
        mx = SimpleNamespace(gpu='gpu', float32=np.float32, int32=np.int32,
            set_default_device=lambda device: None, set_cache_limit=lambda size: None,
            stream=lambda device: nullcontext(), array=np.array, stack=np.stack,
            logsumexp=lambda a, **kwargs: np.logaddexp.reduce(a, **kwargs),
            softmax=lambda a: np.exp(a - np.max(a)) / np.exp(a - np.max(a)).sum(),
            eval=lambda *args: None, synchronize=lambda: None, clear_cache=lambda: None)
        modules = {'mlx': SimpleNamespace(core=mx), 'mlx.core': mx,
                   'mlx.utils': SimpleNamespace(tree_flatten=lambda values: list(values.items())),
                   'mlx_vlm': SimpleNamespace(load=load),
                   'mlx_vlm.utils': SimpleNamespace(prepare_inputs=prepare_inputs),
                   'mlx_lm.models.cache': SimpleNamespace(make_prompt_cache=lambda lm: lm.make_cache())}
        context = patch.dict(sys.modules, modules)
        context.start()
        self.addCleanup(context.stop)
        with patch('vision_ranker.manifest', return_value={'vision': {'repo': 'test/vision'}}), \
             patch('vision_ranker.validate_models', return_value={'vision': Path('/verified/vision')}):
            ranker = cls(Path('/unused'))
        return ranker, model, processor, calls, prepared

    def test_loads_one_verified_model_and_text_uses_same_language_weights(self):
        ranker, model, processor, calls, _ = self.setup_ranker()
        self.assertEqual(calls, [(('/verified/vision',), dict(trust_remote_code=False, use_fast=False))])
        self.assertIs(ranker.engine.lm.language_model, model.language_model)
        self.assertIs(ranker.engine.text, model.language_model.model)
        self.assertIs(ranker.tok, processor.tokenizer)
        self.assertEqual(ranker.model_info['engine'], 'Qwen3.5/MLX-VLM')
        self.assertTrue(ranker.model_info['vision'])
        self.assertEqual(ranker.model_info['quantization'], '4bit')
        self.assertEqual(ranker.model_info['weight_bytes'], 32)

    def test_startup_warms_vision_once_with_synthetic_image_on_same_model(self):
        ranker, model, processor, calls, prepared = self.setup_ranker()
        self.assertEqual(len(prepared), 1, 'Startup must compile vision kernels before the ranker is ready')
        self.assertEqual(len(model.image_caches), 1)
        self.assertEqual(len(calls), 1, 'Vision warmup must use the existing model')
        image = prepared[0][0]
        self.assertEqual((image.mode, image.size), ('RGB', (864, 576)))
        self.assertEqual(image.getextrema(), ((255, 255), (255, 255), (255, 255)))
        self.assertIs(ranker.engine.lm.language_model, model.language_model)
        self.assertIsNot(model.image_caches[0], ranker.continuation_scorer.cached_prefix[0])
        self.assertNotIn('image', ranker.__dict__)

    def test_only_continuation_strategy_is_supported_and_scores_keep_safe_order(self):
        cls = self.ranker_type()
        ranker = cls.__new__(cls)
        for scores, order, inferred in [([-4, -2, -2], [1, 2, 0], True),
                                       ([-2, -2, -2], [0, 1, 2], True),
                                       ([math.nan, -1, -2], [0, 1, 2], False),
                                       (None, [0, 1, 2], False)]:
            ranker.continuation_scorer = SimpleNamespace(score=lambda *args, **kwargs:
                dict(scores=scores, context_tokens=3, cache_hit=True))
            result = ranker.rank('context', 'word', ['a', 'b', 'b'])
            self.assertEqual(result['order'], order)
            self.assertIs(result['inferred'], inferred)
        with self.assertRaises(ValueError):
            ranker.rank('context', 'word', ['a', 'b'], strategy='kev')

    def test_screenshot_uses_disposable_cache_and_retained_text_scores_are_unchanged(self):
        ranker, model, processor, calls, prepared = self.setup_ranker()
        initial_prepared = len(prepared)
        before = ranker.continuation_scorer.score('context', ['short', 'long'])
        retained = ranker.continuation_scorer.cached_prefix
        state = retained[0][0].state
        image = Image.new('RGB', (32, 24), 'white')
        for _ in range(2):
            result = ranker.screen_language(image)
            self.assertIn(result['language'], {'chinese', 'english', 'uncertain'})
            self.assertTrue(0 <= result['english_score'] <= 1)
        after = ranker.continuation_scorer.score('context', ['short', 'long'])
        self.assertTrue(after['cache_hit'])
        self.assertEqual(before['scores'], after['scores'])
        self.assertIs(ranker.continuation_scorer.cached_prefix, retained)
        self.assertEqual(retained[0][0].state, state)
        self.assertIsNot(model.image_caches[0], model.image_caches[1])
        self.assertIsNot(model.image_caches[0], retained[0])
        self.assertEqual(len(calls), 1)
        self.assertEqual(len(prepared), initial_prepared + 2)
        self.assertNotIn('image', ranker.__dict__)
        content = processor.messages[-1][0][-1]['content']
        for expected in ['A: 中文', 'B: 英文', '蓝色', 'URL', 'email', 'code', 'data']:
            self.assertIn(expected, content)
        self.assertFalse(processor.messages[-1][1]['enable_thinking'])

    def test_cap_keeps_one_hundred_tokens_and_instances_do_not_share_cache(self):
        cls = self.ranker_type()
        ranker = cls.__new__(cls)
        ranker.tok = Tokenizer()
        self.assertEqual(ranker.cap('中' * 512), '中' * 100)
        self.assertEqual(ranker.cap('中文'), '中文')
        self.assertEqual(len(ranker._capped_prefixes), 2)


if __name__ == '__main__':
    unittest.main()
