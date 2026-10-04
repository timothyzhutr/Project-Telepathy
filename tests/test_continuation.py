"""Continuation sums use joint tokens and isolated real MLX cache branches."""
import importlib.util
import inspect
import math
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path[:0] = [str(Path(__file__).resolve().parents[1] / 'worker')]
from kev_ranker import KevRanker


class Tokenizer:
    pad_token_id = 0
    all_special_ids = [15]
    encodings = {
        'context': [1, 2, 3],
        'contextshort': [1, 2, 9, 4],  # joint boundary replaces the prefix's last token
        'contextlong': [1, 2, 3, 5, 6, 7],
        'contextsame': [1, 2, 3, 5],
        'changed': [1, 8, 3],
        'changedshort': [1, 8, 9, 4],
        'changedlong': [1, 8, 3, 5, 6, 7],
        'other': [10],
        'othershort': [11, 4],
        'special': [1, 15],
        'contextspecial': [1, 2, 3, 15],
    }

    def __call__(self, text, add_special_tokens=False):
        return SimpleNamespace(input_ids=self.encodings.get(text, []))


class ContinuationTests(unittest.TestCase):
    def scorer(self):
        specification = importlib.util.find_spec('continuation_scorer')
        self.assertIsNotNone(specification, 'Production continuation scorer is missing')
        from continuation_scorer import ContinuationScorer
        import mlx.core as mx
        from mlx_lm.models.qwen2 import Model, ModelArgs
        mx.random.seed(17)
        model = Model(ModelArgs(model_type='qwen2', hidden_size=16, num_hidden_layers=1,
            intermediate_size=32, num_attention_heads=2, num_key_value_heads=2,
            rms_norm_eps=1e-5, vocab_size=16))
        model.eval()
        mx.eval(model.parameters())
        ranker = SimpleNamespace(mx=mx, tok=Tokenizer(), cap=lambda prefix: prefix,
            engine=SimpleNamespace(lm=SimpleNamespace(language_model=model, layers=model.layers),
                                   text=model.model))
        return ContinuationScorer(ranker), ranker, model

    def reference(self, ranker, model, tokens, start):
        mx = ranker.mx
        logits = model(mx.array([tokens[:-1]], dtype=mx.int32)).astype(mx.float32)
        log_probs = logits - mx.logsumexp(logits, axis=-1, keepdims=True)
        return sum(log_probs[0, i-1, tokens[i]].item() for i in range(start, len(tokens)))

    def test_joint_boundary_and_variable_lengths_match_full_likelihood_sums(self):
        scorer, ranker, model = self.scorer()
        result = scorer.score('context', ['short', 'long'], use_cache=False)
        for value, word in zip(result['scores'], ['short', 'long']):
            expected = self.reference(ranker, model, Tokenizer.encodings['context'+word], 2)
            self.assertAlmostEqual(value, expected, places=5)
        self.assertFalse(result['cache_hit'])
        self.assertEqual(result['context_tokens'], 3)

    def test_shared_candidate_tokens_are_part_of_the_likelihood_sum(self):
        scorer, ranker, model = self.scorer()
        result = scorer.score('context', ['same', 'long'])
        for value, word in zip(result['scores'], ['same', 'long']):
            self.assertAlmostEqual(value, self.reference(ranker, model,
                Tokenizer.encodings['context'+word], 3), places=5)

    def test_cache_reuse_and_changed_batch_do_not_mutate_prefix(self):
        scorer, _, _ = self.scorer()
        first = scorer.score('context', ['short', 'long'])
        second = scorer.score('context', ['long', 'short', 'short'])
        third = scorer.score('context', ['short', 'long'])
        self.assertFalse(first['cache_hit'])
        self.assertTrue(second['cache_hit'])
        self.assertTrue(third['cache_hit'])
        for actual, expected in zip(second['scores'], [first['scores'][1], first['scores'][0], first['scores'][0]]):
            self.assertAlmostEqual(actual, expected, places=5)
        self.assertEqual(third['scores'], first['scores'])

    def test_fresh_scoring_does_not_replace_or_reuse_a_cached_prefix(self):
        scorer, _, _ = self.scorer()
        first = scorer.score('context', ['short', 'long'])
        uncached = scorer.score('changed', ['short', 'long'], use_cache=False)
        after = scorer.score('context', ['short', 'long'])
        self.assertFalse(uncached['cache_hit'])
        self.assertTrue(after['cache_hit'])
        self.assertEqual(first['scores'], after['scores'])
        self.assertNotEqual(first['scores'], uncached['scores'])

    def test_changed_context_invalidates_prefix(self):
        scorer, _, _ = self.scorer()
        scorer.score('context', ['short', 'long'])
        self.assertFalse(scorer.score('changed', ['short', 'long'])['cache_hit'])
        self.assertFalse(scorer.score('context', ['short', 'long'])['cache_hit'])

    def test_no_context_and_unscorable_boundary_are_safe(self):
        scorer, _, _ = self.scorer()
        for prefix in ['', '   ', 'other']:
            result = scorer.score(prefix, ['short', 'long'])
            self.assertIsNone(result['scores'])
            self.assertFalse(result['cache_hit'])

    def test_control_token_candidates_do_not_become_scored_special_tokens(self):
        scorer, _, _ = self.scorer()
        self.assertIsNone(scorer.score('context', ['short', 'special'])['scores'])


class ContinuationRankTests(unittest.TestCase):
    def ranker(self, scores):
        self.assertIn('strategy', inspect.signature(KevRanker.rank).parameters,
                      'Optional continuation strategy is missing')
        ranker = KevRanker.__new__(KevRanker)
        ranker.continuation_scorer = SimpleNamespace(score=lambda *args, **kwargs:
            dict(scores=scores, context_tokens=3, cache_hit=kwargs.get('use_cache', True)))
        return ranker

    def test_optional_strategy_ranks_by_sum_and_preserves_ties_and_duplicates(self):
        result = self.ranker([-4.0, -2.0, -2.0, -4.0]).rank(
            'context', 'pinyin', ['long', 'short', 'short', 'long'], strategy='continuation')
        self.assertEqual(result['order'], [1, 2, 0, 3])
        self.assertEqual(result['selected_index'], 1)
        self.assertFalse(result['keep'])
        self.assertEqual(result['context_tokens'], 3)
        self.assertTrue(result['cache_hit'])
        self.assertEqual(result['ranker'], 'continuation')
        self.assertGreaterEqual(result['request_ms'], 0)

    def test_unusable_scores_keep_original_order(self):
        for scores in [None, [], [-1], [math.nan, -2], [-1, math.inf], [-math.inf, -2]]:
            with self.subTest(scores=scores):
                result = self.ranker(scores).rank('context', 'x', ['a', 'b'], strategy='continuation')
                self.assertEqual(result['order'], [0, 1])
                self.assertIsNone(result['selected_index'])
                self.assertTrue(result['keep'])

    def test_all_equal_scores_keep_original_order(self):
        result = self.ranker([-2, -2]).rank('context', 'x', ['a', 'b'], strategy='continuation')
        self.assertEqual(result['order'], [0, 1])
        self.assertTrue(result['keep'])
        self.assertIsNone(result['selected_index'])

    def test_unknown_strategy_is_rejected(self):
        with self.assertRaises(ValueError):
            self.ranker([-1, -2]).rank('context', 'x', ['a', 'b'], strategy='unsupported')


if __name__ == '__main__':
    unittest.main()
