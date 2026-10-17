"""Checks prevent malformed model output and errors from inflating the report."""
import unittest
from benchmark import validate_answer, summarize


class ReportTests(unittest.TestCase):
    def test_incomplete_or_nonfinite_probabilities_are_rejected(self):
        for probabilities in [{'english': 1}, {'english': .6, 'chinese': .3, 'uncertain': .3},
                              {'english': float('nan'), 'chinese': 0, 'uncertain': 0}]:
            with self.assertRaises(ValueError):
                validate_answer({'choice': 'english', 'probabilities': probabilities})

    def test_choice_must_match_the_distribution(self):
        with self.assertRaises(ValueError):
            validate_answer({'choice': 'chinese', 'probabilities':
                             {'english': .9, 'chinese': .05, 'uncertain': .05}})

    def test_errors_remain_in_the_quality_denominator(self):
        rows = [{'id': 'a', 'mode': 'image', 'group': 'context', 'expected': 'chinese',
                 'choice': 'chinese', 'probabilities': {'chinese': .9, 'english': .05, 'uncertain': .05},
                 'client_ms': 200},
                {'id': 'b', 'mode': 'image', 'group': 'context', 'expected': 'english',
                 'error': 'timeout'}]
        summary = summarize(rows)
        self.assertEqual(summary['attempts'], 2)
        self.assertEqual(summary['matches'], 1)
        self.assertEqual(summary['errors'], 1)
        self.assertEqual(summary['fraction_matching'], .5)
        self.assertEqual(summary['latency_ms']['samples'], 1)


if __name__ == '__main__':
    unittest.main()
