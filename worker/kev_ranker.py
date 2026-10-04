"""Offline context prediction and alternative Kev pointer-head decisions."""
import math,os,time
from collections import OrderedDict
from model_store import validate_models,manifest
from prompt import build_request
class KevRanker:
    def __init__(self,model_root,*,quantization='mxfp8'):
        paths=validate_models(model_root,manifest())
        os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',TOKENIZERS_PARALLELISM='false',PYTORCH_ENABLE_MPS_FALLBACK='0')
        import torch
        import mlx.core as mx
        from kev.checkpoint import Checkpoint
        from kev.model import load_tokenizer,pad_id,admit,user_tokens
        from kev.mlx_model import load_base,merge_lora,MLXDecisionModel
        from kev.api import SystemOneRequest,to_record,to_answers
        torch.set_num_threads(4);mx.set_default_device(mx.gpu)
        ck=Checkpoint(paths['kev'])
        # Use local directories explicitly; no model lookup or download at inference time.
        self.tok=load_tokenizer(str(paths['base']))
        lm=load_base(paths['base']);merge_lora(lm,paths['kev'],1.0)
        self.engine=MLXDecisionModel(lm,pad_id(self.tok),head_dim=ck.meta.head_dim)
        self.engine.head.load_state_dict(ck.meta.head);self.engine.eval()
        self.engine.head.temperature=ck.meta.temperature
        # The official head reads the original embedding width. Pack weights
        # after initializing it, but before caches/warm-up can retain BF16 state.
        from model_precision import configure_backbone
        self.model_info=configure_backbone(lm,quantization)
        self.torch,self.mx=torch,mx
        self.user_tokens=user_tokens
        self.request_type,self.record,self.answers,self.admit=SystemOneRequest,to_record,to_answers,admit
        from mlx_lm.models.cache import make_prompt_cache
        from ranking_cache import RankingCache
        def prefill(key):
            cache=make_prompt_cache(self.engine.lm)
            if key:
                self.engine.text(mx.array([key],dtype=mx.int32),cache=cache)
                mx.eval([c.state for c in cache])
            return len(key),cache
        def copy(prefix):
            length,cache=prefix
            return length,[type(c).merge([c]) for c in cache]
        def branch(enc,prefix):
            length,cache=prefix
            hidden=self.engine._hidden([enc['ids'][length:]],cache=cache)[0]
            logits=self.engine._logits(hidden,enc['decide_idx'][0]-length,
                                       [i-length for i in enc['opt_idx'][0]])
            return [torch.softmax(logits,dim=-1)]
        self.ranking_cache=RankingCache(prefill,branch,copy)
        from language_router import LanguageRouter
        self.language_router=LanguageRouter(self)
        from continuation_scorer import ContinuationScorer
        self.continuation_scorer=ContinuationScorer(self)
        self.rank('这个类可以','jicheng',['集成','继承'],strategy='kev')
        # Compile the LM vocabulary head and copied-cache suffix path before
        # the worker reports ready, rather than during the first typed word.
        self.route('I think ','he',['和','喝','何'])
        self.route('这个职位拥有决定预算分配的','quanli',['权力','权利','全力','劝离','圈里','泉里','拳理','全利','全礼','犬吏','全里','全离'])
        self.rank('这个职位拥有决定预算分配的','quanli',['权力','权利','全力','劝离','圈里','泉里','拳理','全利','全礼','犬吏','全里','全离'])
    def cap(self,prefix):
        # Instance-owned caches cannot keep a replaced model alive. Offsets
        # jump directly to the token budget; re-encode to verify BPE boundaries.
        cache=self.__dict__.setdefault('_capped_prefixes',OrderedDict())
        if prefix in cache:
            cache.move_to_end(prefix);return cache[prefix]
        original=prefix
        encoded=self.tok(prefix,add_special_tokens=False,return_offsets_mapping=True)
        while len(encoded.input_ids)>100:
            start=max(1,encoded.offset_mapping[-100][0])
            prefix=prefix[start:]
            encoded=self.tok(prefix,add_special_tokens=False,return_offsets_mapping=True)
        cache[original]=prefix
        if len(cache)>32:cache.popitem(last=False)
        return prefix
    def stable_tokens(self,prefix):
        # Tokenization can merge at the boundary. RankingCache intersects this
        # prefix with the actual encoding before reusing any recurrent state.
        cached=self.__dict__.get('_stable_tokens')
        if cached is None or cached[0]!=prefix:
            tokens=[self.tok.convert_tokens_to_ids('<|fim_prefix|>')]+self.user_tokens(self.tok,'prefix: '+prefix+'\npinyin:')
            self._stable_tokens=(prefix,tokens)
        return self._stable_tokens[1]
    def rank(self,prefix,pinyin,words,use_cache=True,*,strategy='continuation'):
        started=time.perf_counter()
        if strategy not in ('kev','continuation'):
            raise ValueError('Unknown ranking strategy: '+str(strategy))
        if strategy=='continuation':
            scored=self.continuation_scorer.score(prefix,words,use_cache=use_cache)
            scores=scored['scores'];original=list(range(len(words)))
            usable=(scores is not None and len(scores)==len(words) and bool(scores)
                    and all(math.isfinite(value) for value in scores))
            keep=not usable or max(scores)==min(scores)
            order=original if keep else sorted(original,key=lambda i:-scores[i])
            return dict(order=order,selected_index=None if keep else order[0],keep=keep,
                inferred=usable,
                request_ms=(time.perf_counter()-started)*1000,
                context_tokens=scored['context_tokens'],cache_hit=scored['cache_hit'],ranker='continuation')
        request=build_request(self.cap(prefix),pinyin,words)
        rec,meta=self.record(self.request_type.model_validate(request))
        enc=self.admit(self.engine,self.tok,rec,truncate=False)
        with self.torch.inference_mode(),self.mx.stream(self.mx.gpu):
            probs=(self.ranking_cache.score(enc,self.stable_tokens(request['state']['prefix']))
                   if use_cache else self.engine.probs(enc))
            self.mx.synchronize()
        answer=self.answers([p.tolist() for p in probs],meta)['candidate']
        choice=answer['choice'];distribution=answer['probabilities']
        order=sorted(range(len(words)),key=lambda i:(-distribution[f'c{i}'],f'c{i}'!=choice))
        keep=choice=='keep'
        return dict(order=list(range(len(words))) if keep else order,selected_index=None if keep else int(choice[1:]),keep=keep,
            inferred=True,
            request_ms=(time.perf_counter()-started)*1000,context_tokens=len(self.tok(request['state']['prefix'],add_special_tokens=False).input_ids),
            cache_hit=use_cache and self.ranking_cache.hit)
    def route(self,prefix,raw,chinese):
        return self.language_router.route(prefix,raw,chinese)
