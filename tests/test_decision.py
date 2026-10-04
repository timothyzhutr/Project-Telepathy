import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
from decision import DecisionService
class Ranker:
    seen=None
    def cap(self,p): return p
    def rank(self,prefix,pinyin,words):
        self.seen=(prefix,pinyin,words)
        return dict(order=list(reversed(range(len(words)))),selected_index=len(words)-1,keep=False,request_ms=10)
class DecisionTests(unittest.TestCase):
    def request(self,**kw):
        return dict(revision=12,prefix='这个职位拥有决定预算分配的',pinyin='quanli',pending='quanli',candidates=['权利','全','权力'],candidate_ends=[6,4,6],**kw)
    def test_rank_remaps_visible_indexes_and_excludes_shorter_fragments(self):
        ranker=Ranker(); result=DecisionService(ranker).decision(self.request())
        self.assertEqual(result.get('order'),[2,0,1]);self.assertEqual(result['revision'],12)
        self.assertEqual(ranker.seen[2],['权利','权力'])
    def test_partial_selection_uses_remaining_pinyin(self):
        ranker=Ranker();body=self.request();body.update(prefix='全',pending='li',candidates=['力','里'],candidate_ends=[6,6])
        DecisionService(ranker).decision(body)
        self.assertEqual(ranker.seen,('全','li',['力','里']))
    def test_missing_model_or_unknown_coverage_falls_back(self):
        self.assertEqual(DecisionService().decision(self.request())['status'],'unavailable')
        body=self.request();body['candidate_ends']=[-1,-1,-1]
        self.assertEqual(DecisionService(Ranker()).decision(body)['status'],'unavailable')
    def test_only_one_full_phrase_skips_model(self):
        body=self.request();body.update(pinyin='butaixing',pending='butaixing',candidates=['不太行','不'],candidate_ends=[9,2])
        result=DecisionService(Ranker()).decision(body)
        self.assertEqual(result.get('order'),[0,1]);self.assertFalse(result['ranked'])
    def test_continuation_strategy_preserves_native_index_mapping(self):
        class ContinuationRanker(Ranker):
            def rank(self,prefix,pinyin,words,*,strategy='kev'):
                result=super().rank(prefix,pinyin,words)
                return dict(result,strategy=strategy)
        result=DecisionService(ContinuationRanker()).decision(self.request(strategy='continuation'))
        self.assertEqual(result['strategy'],'continuation')
        self.assertEqual(result['order'],[2,0,1]);self.assertEqual(result['selected_index'],2)
    def test_unsupported_strategy_is_rejected(self):
        for value in ('unknown',None,[],True):
            with self.assertRaises(ValueError):
                DecisionService(Ranker()).decision(self.request(strategy=value))
    def test_rejects_invalid_snapshot(self):
        for field,value in [('revision',True),('pending','not pinyin'),('candidates',['x']*13),('candidate_ends',[10]*3)]:
            body=self.request();body[field]=value
            with self.assertRaises(ValueError): DecisionService(Ranker()).decision(body)
if __name__=='__main__': unittest.main()
