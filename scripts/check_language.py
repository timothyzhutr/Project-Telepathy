"""Reproduce the synthetic context-routing check with separately installed weights.

This is an exploratory fixture set, not a calibrated or held-out accuracy test.
Captured candidates come from the packaged, non-learning Wanxiang profile.
"""
import argparse,json,statistics,sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'worker'),str(ROOT/'vendor/kev')]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--model-dir',type=Path,default=Path.home()/'Library/Application Support/Telepathy/models')
    parser.add_argument('--cases',type=Path,default=ROOT/'experiments/language-routing/cases.json')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--quantization',choices=['mxfp8','bf16'],default='mxfp8')
    args=parser.parse_args()
    from kev_ranker import KevRanker
    from decision import DecisionService
    ranker=KevRanker(args.model_dir,quantization=args.quantization);service=DecisionService(ranker)
    rows=[]
    for revision,case in enumerate(json.loads(args.cases.read_text()),1):
        snapshot={k:case[k] for k in ('prefix','pinyin','pending','candidates','candidate_ends')}
        result=service.language(dict(snapshot,revision=revision))
        rows.append(dict(id=case['id'],expected=case['expected'],category=case['category'],result=result))
        print(case['id'],case['expected'],result['language'],round(result.get('request_ms',0)),flush=True)
    for group in sorted({r['category'] for r in rows}):
        selected=[r for r in rows if r['category']==group]
        print(group,dict(matched=sum(r['expected']==r['result']['language'] for r in selected),
            cases=len(selected),false_english=sum(r['expected']=='chinese' and r['result']['language']=='english' for r in selected),
            median_ms=round(statistics.median(r['result']['request_ms'] for r in selected),1)))
    # Cache branches must not mutate the cached prefix or change its scores.
    prefix='I think ';words=['和','喝','何']
    first=ranker.route(prefix,'he',words);second=ranker.route(prefix,'he',words)
    assert abs(first['english_score']-second['english_score'])<1e-5,(first,second)
    ranker.route('天气很热，我们买点水来','he',words)
    fresh=ranker.route(prefix,'he',words)
    assert abs(first['english_score']-fresh['english_score'])<1e-5,(first,fresh)
    assert ranker.rank('作为消费者，我们有依法要求商家提供合格产品的','quanli',['权力','权利'],strategy='kev')['selected_index']==1
    print('PASS: cache reuse, context invalidation and unchanged pointer ranking')
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
