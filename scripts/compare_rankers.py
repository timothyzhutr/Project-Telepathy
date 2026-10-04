"""Offline synthetic comparison; never changes the installed input method.

Natural continuation scores use the same merged backbone and calculation as
language routing. They are likelihoods, not calibrated intention probabilities.
"""
import argparse,json,statistics,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'worker'),str(ROOT/'vendor/kev')]

def continuation_scores(ranker,prefix,raw,words):
    from mlx_lm.models.cache import make_prompt_cache
    mx=ranker.mx;lm=ranker.engine.lm;text=ranker.engine.text
    started=time.perf_counter()
    prefix=ranker.cap(prefix)
    sequences=[ranker.tok(prefix+w,add_special_tokens=False).input_ids for w in words+[raw]]
    common=0
    while common<min(map(len,sequences)) and len({s[common] for s in sequences})==1:common+=1
    common=min(common,min(map(len,sequences))-1)
    if common<=0:raise ValueError('This offline comparison needs some common preceding context')
    def logits(hidden):
        head=getattr(lm.language_model,'lm_head',None)
        return head(hidden) if head is not None else text.embed_tokens.as_linear(hidden)
    with mx.stream(mx.gpu):
        cache=make_prompt_cache(lm)
        hidden=text(mx.array([sequences[0][:common]],dtype=mx.int32),cache=cache)
        first=logits(hidden[:,-1,:]);first=first-mx.logsumexp(first,axis=-1,keepdims=True)
        mx.eval(first,[c.state for c in cache])
        remaining=[s[common:] for s in sequences];width=max(map(len,remaining))
        if width>1:
            copied=[type(c).merge([c]*len(sequences)) for c in cache]
            ids=mx.array([s[:-1]+[ranker.tok.pad_token_id]*(width-len(s)) for s in remaining],dtype=mx.int32)
            hidden=text(ids,cache=copied)
            tail=logits(hidden);tail=tail-mx.logsumexp(tail,axis=-1,keepdims=True)
        values=[]
        for i,tokens in enumerate(remaining):
            total=first[0,tokens[0]]
            for j in range(1,len(tokens)):total=total+tail[i,j-1,tokens[j]]
            values.append(total)
        values=mx.stack(values);mx.eval(values);mx.synchronize()
    return values.tolist()[:-1],(time.perf_counter()-started)*1000

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--model-dir',type=Path,default=Path.home()/'Library/Application Support/Telepathy/models')
    parser.add_argument('--cases',type=Path,default=ROOT/'experiments/language-routing/cases.json')
    parser.add_argument('--labels',type=Path,default=ROOT/'experiments/prediction/labels.json')
    parser.add_argument('--output',type=Path)
    parser.add_argument('--quantization',choices=['mxfp8','bf16'],default='mxfp8')
    args=parser.parse_args()
    from kev_ranker import KevRanker
    ranker=KevRanker(args.model_dir,quantization=args.quantization)
    cases=[c for c in json.loads(args.cases.read_text()) if c['category']=='chinese-regression']
    labels=json.loads(args.labels.read_text())
    original_answers=ranker.answers
    probabilities={}
    def observe(probs,meta):
        result=original_answers(probs,meta)
        probabilities.clear();probabilities.update(result['candidate']['probabilities'])
        return result
    ranker.answers=observe
    rows=[]
    for case in cases:
        words=[w for w,e in zip(case['candidates'],case['candidate_ends']) if e>=case['candidate_ends'][0]]
        decision=ranker.rank(case['prefix'],case['pending'],words,use_cache=False)
        chosen=words[0] if decision['keep'] else words[decision['selected_index']]
        scores,elapsed=continuation_scores(ranker,case['prefix'],case['pending'],words)
        natural=words[max(range(len(words)),key=scores.__getitem__)]
        no_keep=words[max(range(len(words)),key=lambda i:probabilities['c'+str(i)])]
        rows.append(dict(id=case['id'],words=words,acceptable=labels[case['id']],baseline=words[0],
                         target_supplied=any(w in labels[case['id']] for w in words),
                         kev=chosen,kev_keep=decision['keep'],kev_ms=decision['request_ms'],
                         ignore_keep=no_keep,continuation=natural,continuation_ms=elapsed,
                         log_likelihoods=scores,probabilities=dict(probabilities)))
    summary=dict(quantization=args.quantization,cases=len(rows),target_supplied=sum(r['target_supplied'] for r in rows))
    for arm in ['baseline','kev','ignore_keep','continuation']:
        summary[arm+'_correct']=sum(r[arm] in r['acceptable'] for r in rows)
    for arm in ['kev','continuation']:
        summary[arm+'_median_ms']=statistics.median(r[arm+'_ms'] for r in rows)
    if args.output:
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(dict(summary=summary,rows=rows),ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(summary,indent=2))

if __name__=='__main__':main()
