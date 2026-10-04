import math
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'worker'))
from language_router import LanguageRouter
import test_continuation


class LanguageScoringTests(unittest.TestCase):
    def test_router_matches_fp32_continuation_scores_on_bf16_backbone(self):
        scorer, ranker, model = test_continuation.ContinuationTests().scorer()
        from mlx.utils import tree_map
        model.update(tree_map(lambda value: value.astype(ranker.mx.bfloat16), model.parameters()))
        ranker.continuation_scorer = scorer
        scores = scorer.score('context', ['short', 'long'])['scores']
        maximum = max(scores)
        weights = [math.exp(value-maximum) for value in scores]
        expected = weights[-1] / sum(weights)
        result = LanguageRouter(ranker).route('context', 'long', ['short'])
        self.assertAlmostEqual(result['english_score'], expected, places=6)

    def test_empty_context_does_not_guess_language(self):
        scorer, ranker, _ = test_continuation.ContinuationTests().scorer()
        ranker.continuation_scorer = scorer
        for prefix in ('', '   '):
            self.assertEqual(LanguageRouter(ranker).route(prefix, 'long', ['short'])['language'], 'uncertain')
