"""Cache keys must match actual encoded tokens; copied branches cannot poison a prefix."""
import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))
from ranking_cache import RankingCache

class Backend:
    def __init__(self): self.prefills=[]; self.branches=[]
    def prefix(self, key):
        self.prefills.append(tuple(key)); return list(key)
    def branch(self, encoded, prefix):
        # Stand in for attention + recurrent state mutations during suffix evaluation.
        self.branches.append(tuple(prefix)); prefix.append(999)
        return encoded['ids'][-1]
    def copy(self, prefix): return list(prefix)

class CacheTests(unittest.TestCase):
    def setup_cache(self):
        backend=Backend()
        return RankingCache(backend.prefix, backend.branch, backend.copy),backend
    def test_reuses_stable_context_when_pinyin_changes(self):
        cache,b=self.setup_cache()
        for raw in (5,6,7):
            self.assertEqual(cache.score({'ids':[1,2,3,raw,9]}, [1,2,3]),9)
        self.assertEqual(b.prefills,[(1,2,3)])
        self.assertEqual(b.branches,[(1,2,3)]*3)
    def test_key_uses_actual_common_tokens_after_boundary_merges(self):
        cache,b=self.setup_cache()
        cache.score({'ids':[1,2,8,5,9]}, [1,2,3])
        self.assertEqual(b.prefills,[(1,2)])
        cache.score({'ids':[1,4,8,5,9]}, [1,2,3])
        self.assertEqual(b.prefills,[(1,2),(1,)])
    def test_changed_context_invalidates_cached_recurrent_state(self):
        cache,b=self.setup_cache()
        cache.score({'ids':[1,2,3,5,9]}, [1,2,3])
        cache.score({'ids':[1,4,3,5,9]}, [1,4,3])
        cache.score({'ids':[1,2,3,5,9]}, [1,2,3])
        self.assertEqual(b.prefills,[(1,2,3),(1,4,3),(1,2,3)])
    def test_failure_does_not_store_partial_prefix(self):
        cache,b=self.setup_cache()
        original=cache.prefill
        def fail(key): raise RuntimeError('incomplete GPU evaluation')
        cache.prefill=fail
        with self.assertRaises(RuntimeError):cache.score({'ids':[1,2,9]}, [1,2])
        cache.prefill=original
        cache.score({'ids':[1,2,9]}, [1,2])
        self.assertEqual(b.prefills,[(1,2)])
    def test_empty_common_prefix_and_short_prefix_are_safe(self):
        cache,b=self.setup_cache()
        self.assertEqual(cache.score({'ids':[4,9]}, [1,2]),9)
        self.assertEqual(b.prefills,[()])
    def test_cache_never_includes_question_or_readout_tokens(self):
        cache,b=self.setup_cache()
        cache.score({'ids':[1,2,3,9], 'state_tokens':2}, [1,2,3,9])
        self.assertEqual(b.prefills,[(1,2)])

if __name__=='__main__':unittest.main()
