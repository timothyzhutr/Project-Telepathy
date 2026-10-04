import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from check_ranking_cache import near_tie

def pair(reference,cached):
    def result(probabilities):
        key=max(probabilities,key=probabilities.get)
        return dict(probabilities=probabilities,keep=key=='keep',
                    selected_index=None if key=='keep' else int(key[1:]))
    return dict(reference=result(reference),cached=result(cached))

class CacheValidationTests(unittest.TestCase):
    def test_keep_flip_inside_one_percentage_point_is_reportable_near_tie(self):
        self.assertTrue(near_tie(pair(dict(c0=.2701,keep=.2761),dict(c0=.2747,keep=.2719))))
    def test_larger_reference_choice_gap_is_not_excused_by_numeric_tolerance(self):
        self.assertFalse(near_tie(pair(dict(c0=.300,keep=.315),dict(c0=.317,keep=.300))))

if __name__=='__main__':unittest.main()
