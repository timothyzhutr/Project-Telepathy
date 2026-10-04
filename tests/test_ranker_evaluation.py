"""Evaluation separates candidate retrieval, routing and eligible ranking."""
import importlib.util
import sys
import unittest
from pathlib import Path
sys.path[:0] = [str(Path(__file__).resolve().parents[1] / 'scripts')]


class EvaluationTests(unittest.TestCase):
    def evaluation(self):
        self.assertIsNotNone(importlib.util.find_spec('evaluate_rankers'), 'Production-path evaluation is missing')
        import evaluate_rankers
        return evaluate_rankers

    def test_summary_counts_supplied_targets_separately_and_no_fit_keeps(self):
        evaluation = self.evaluation()
        rows = [
            dict(acceptable=['鱼'], target_supplied=True, category='short', baseline='于', route='chinese',
                 kev='鱼', continuation='鱼', kev_keep=False, continuation_keep=False,
                 ranked=True, kev_ms=10, kev_cached_ms=6, continuation_ms=7, continuation_cached_ms=4,
                 kev_cache_hit=True, continuation_cache_hit=True, kev_cache_choice_changed=False, continuation_cache_choice_changed=False),
            dict(acceptable=['曦'], target_supplied=False, category='names', baseline='西', route='chinese',
                 kev='西', continuation='西', kev_keep=True, continuation_keep=False,
                 ranked=True, kev_ms=12, kev_cached_ms=6, continuation_ms=8, continuation_cached_ms=4,
                 kev_cache_hit=True, continuation_cache_hit=True, kev_cache_choice_changed=False, continuation_cache_choice_changed=False),
            dict(acceptable=[], target_supplied=False, category='no-fit', baseline='毛', route='chinese',
                 kev='毛', continuation='猫', kev_keep=True, continuation_keep=False,
                 ranked=True, kev_ms=11, kev_cached_ms=7, continuation_ms=9, continuation_cached_ms=5,
                 kev_cache_hit=True, continuation_cache_hit=True, kev_cache_choice_changed=False, continuation_cache_choice_changed=False),
        ]
        result = evaluation.summarize(rows)
        self.assertEqual(result['labeled_cases'], 2)
        self.assertEqual(result['target_supplied'], 1)
        self.assertEqual(result['missing_target'], 1)
        self.assertEqual(result.get('inference_after_english_routing'), 3)
        self.assertEqual(result['continuation_correct_when_target_supplied'], 1)
        self.assertEqual(result['no_fit_cases'], 1)
        self.assertEqual(result['kev_no_fit_keep'], 1)
        self.assertEqual(result['continuation_no_fit_keep'], 0)
        self.assertEqual(result['kev_median_fresh_ms'], 11)
        self.assertEqual(result['continuation_median_cached_ms'], 4)

    def test_production_coverage_filter_keeps_shorter_candidates_after_ranked_words(self):
        evaluation = self.evaluation()
        class Ranker:
            def rank(self, prefix, raw, words, use_cache=True, *, strategy='kev'):
                return dict(order=list(reversed(range(len(words)))), selected_index=len(words)-1,
                            keep=False, request_ms=1, cache_hit=use_cache, context_tokens=1)
            def route(self, *args):
                return dict(language='chinese', request_ms=1)
        case = dict(prefix='context', pinyin='butaixing', pending='butaixing',
                    candidates=['不太行', '不', '步态型'], candidate_ends=[9, 2, 9])
        result = evaluation.evaluate_decision(Ranker(), case, strategy='continuation', use_cache=False)
        self.assertEqual(result['order'], [2, 0, 1])
        self.assertEqual(result['selected_index'], 2)
        self.assertFalse(result['cache_hit'])


if __name__ == '__main__':
    unittest.main()
