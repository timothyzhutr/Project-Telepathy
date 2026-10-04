import gc
import sys
import unittest
import weakref
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))
from kev_ranker import KevRanker


class Tokenizer:
    def __init__(self): self.calls = 0
    def __call__(self, text, **kwargs):
        self.calls += 1
        return SimpleNamespace(input_ids=list(range(len(text))),
                               offset_mapping=[(i, i+1) for i in range(len(text))])
    def convert_tokens_to_ids(self, text): return 1


class ContextCacheTests(unittest.TestCase):
    def ranker(self):
        ranker = KevRanker.__new__(KevRanker)
        ranker.tok = Tokenizer()
        ranker.user_tokens = lambda tok, text: list(range(len(text)))
        return ranker

    def test_long_context_is_capped_without_character_by_character_tokenization(self):
        ranker = self.ranker()
        text = '中文' * 256
        self.assertEqual(ranker.cap(text), text[-100:])
        self.assertLessEqual(ranker.tok.calls, 3)
        calls = ranker.tok.calls
        self.assertEqual(ranker.cap(text), text[-100:])
        self.assertEqual(ranker.tok.calls, calls)

    def test_context_caches_do_not_retain_a_discarded_ranker(self):
        ranker = self.ranker()
        ranker.cap('中文')
        ranker.stable_tokens('中文')
        reference = weakref.ref(ranker)
        del ranker
        gc.collect()
        self.assertIsNone(reference(), 'A model reload must release the old ranker')

    def test_short_context_and_instance_caches_are_independent(self):
        first, second = self.ranker(), self.ranker()
        self.assertEqual(first.cap('中文'), '中文')
        self.assertEqual(second.cap('中文'), '中文')
        self.assertEqual(second.tok.calls, 1)

    def test_cut_boundary_is_retokenized_before_accepting_the_budget(self):
        ranker = self.ranker()
        class BoundaryTokenizer(Tokenizer):
            def __call__(self, text, **kwargs):
                result = super().__call__(text, **kwargs)
                if len(text) <= 100 and text:
                    result.input_ids.insert(0, 999)
                    result.offset_mapping.insert(0, (0, 1))
                return result
        ranker.tok = BoundaryTokenizer()
        self.assertEqual(ranker.cap('中'*512), '中'*99)
        self.assertLessEqual(ranker.tok.calls, 3)
