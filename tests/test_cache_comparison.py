import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from check_ranking_cache import near_tie

def result(index,probabilities,keep=False):
    return dict(selected_index=index,keep=keep,probabilities=probabilities)

class ComparisonTests(unittest.TestCase):
    def test_permits_observed_close_numerical_flip(self):
        self.assertTrue(near_tie(dict(
            reference=result(0,dict(c0=.3592,c1=.3578)),
            cached=result(1,dict(c0=.3510,c1=.3625)))))
    def test_rejects_wrong_reported_choice_even_if_distributions_match(self):
        probabilities=dict(c0=.8,c1=.1,keep=.1)
        self.assertFalse(near_tie(dict(reference=result(0,probabilities),cached=result(1,probabilities))))
        self.assertFalse(near_tie(dict(reference=result(0,probabilities),cached=result(None,probabilities,True))))
    def test_rejects_missing_choice_key(self):
        self.assertFalse(near_tie(dict(reference=result(0,dict(c0=.8)),cached=result(9,dict(c0=.8)))))

if __name__=='__main__':unittest.main()
