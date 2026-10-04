"""Contextual literal-English vs Hanzi scoring with the already loaded backbone.

Scores are normalized likelihoods of the supplied continuations, not calibrated
probabilities of a person's intent. Only a large margin changes the input mode.
"""
import math,time

class LanguageRouter:
    def __init__(self,ranker):
        self.ranker=ranker
        self.cached_key=None
        self.cached_prefix=None

    def route(self,prefix,raw,chinese):
        ranker=self.ranker;mx=ranker.mx;lm=ranker.engine.lm;text=ranker.engine.text
        from mlx_lm.models.cache import make_prompt_cache
        started=time.perf_counter()
        prefix=ranker.cap(prefix)
        words=chinese+[raw]
        sequences=[ranker.tok(prefix+w,add_special_tokens=False).input_ids for w in words]
        common=0
        while common<min(map(len,sequences)) and len({s[common] for s in sequences})==1:common+=1
        common=min(common,min(map(len,sequences))-1)
        if common<=0:
            return dict(language='uncertain',request_ms=0)
        def logits(hidden):
            head=getattr(lm.language_model,'lm_head',None)
            return head(hidden) if head is not None else text.embed_tokens.as_linear(hidden)
        key=tuple(sequences[0][:common])
        with mx.stream(mx.gpu):
            if key!=self.cached_key:
                cache=make_prompt_cache(lm)
                hidden=text(mx.array([key],dtype=mx.int32),cache=cache)
                first=logits(hidden[:,-1,:])
                first=first-mx.logsumexp(first,axis=-1,keepdims=True)
                mx.eval(first,[c.state for c in cache])
                self.cached_key=key;self.cached_prefix=(cache,first)
            cache,first=self.cached_prefix
            remaining=[s[common:] for s in sequences];width=max(map(len,remaining))
            if width>1:
                copied=[type(c).merge([c]*len(words)) for c in cache]
                ids=mx.array([s[:-1]+[ranker.tok.pad_token_id]*(width-len(s)) for s in remaining],dtype=mx.int32)
                hidden=text(ids,cache=copied)
                tail=logits(hidden);tail=tail-mx.logsumexp(tail,axis=-1,keepdims=True)
            values=[]
            for i,tokens in enumerate(remaining):
                total=first[0,tokens[0]]
                for j in range(1,len(tokens)):total=total+tail[i,j-1,tokens[j]]
                values.append(total)
            values=mx.stack(values);mx.eval(values);mx.synchronize()
        scores=values.tolist();maximum=max(scores)
        weights=[math.exp(v-maximum) for v in scores]
        english=weights[-1]/sum(weights)
        if not math.isfinite(english):return dict(language='uncertain',request_ms=0)
        language='english' if english>=.97 else 'chinese' if english<=.03 else 'uncertain'
        return dict(language=language,english_score=english,
                    request_ms=(time.perf_counter()-started)*1000)
