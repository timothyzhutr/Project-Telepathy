import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
from decision import DecisionService

class Ranker:
    def __init__(self):self.routes=[];self.ranks=[]
    def route(self,prefix,raw,words):
        self.routes.append((prefix,raw,words))
        return dict(language='english',request_ms=5,english_score=.99)
    def rank(self,*args):self.ranks.append(args);raise AssertionError('Language judgment must not rerank')

class LanguageTests(unittest.TestCase):
    def body(self):
        return dict(revision=7,prefix='I think ',pinyin='he',pending='he',candidates=['和','喝','何','he'],candidate_ends=[2,2,2,2])
    def test_language_uses_only_full_chinese_continuations_and_preserves_input(self):
        ranker=Ranker();body=self.body();body.update(candidates=['不太行','不','butaixing'],pinyin='butaixing',pending='butaixing',candidate_ends=[9,2,9])
        result=DecisionService(ranker).language(body)
        self.assertEqual(ranker.routes,[(body['prefix'],'butaixing',['不太行'])])
        self.assertEqual(result['language'],'english');self.assertEqual(result['revision'],7)
        self.assertFalse(ranker.ranks)
    def test_missing_model_or_partial_selection_keeps_native_behavior(self):
        self.assertEqual(DecisionService().language(self.body())['language'],'uncertain')
        ranker=Ranker();body=self.body();body['pending']='e'
        self.assertEqual(DecisionService(ranker).language(body)['language'],'uncertain')
        self.assertFalse(ranker.routes)
    def test_english_only_native_candidates_skip_neural_inference(self):
        ranker=Ranker();body=self.body();body.update(pinyin='model',pending='model',candidates=['model','models'],candidate_ends=[5,5])
        result=DecisionService(ranker).language(body)
        self.assertEqual(result['language'],'english');self.assertFalse(ranker.routes)
    def test_rejects_invalid_snapshot_instead_of_guessing(self):
        body=self.body();body['pinyin']='he\x00'
        with self.assertRaises(ValueError):DecisionService(Ranker()).language(body)
    def test_invalid_model_judgment_falls_back(self):
        ranker=Ranker();ranker.route=lambda *args:dict(language='bogus')
        self.assertEqual(DecisionService(ranker).language(self.body())['language'],'uncertain')
    def test_unknown_or_partial_coverage_does_not_assume_english(self):
        ranker=Ranker();body=self.body()
        for ends in ([1,1,1,1],[-1]*4):
            body['candidate_ends']=ends
            self.assertEqual(DecisionService(ranker).language(body)['language'],'uncertain')
        self.assertFalse(ranker.routes)

if __name__=='__main__':unittest.main()
