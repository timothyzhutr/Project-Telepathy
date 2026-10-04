"""Offline MLX inference through Kev's official pointer head and encoder."""
import os,time
from functools import lru_cache
from model_store import validate_models,manifest
from prompt import build_request
class KevRanker:
    def __init__(self,model_root):
        paths=validate_models(model_root,manifest())
        os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',TOKENIZERS_PARALLELISM='false',PYTORCH_ENABLE_MPS_FALLBACK='0')
        import torch
        import mlx.core as mx
        from kev.checkpoint import Checkpoint
        from kev.model import load_tokenizer,pad_id,admit
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
        self.torch,self.mx=torch,mx
        self.request_type,self.record,self.answers,self.admit=SystemOneRequest,to_record,to_answers,admit
        from language_router import LanguageRouter
        self.language_router=LanguageRouter(self)
        self.rank('这个类可以','jicheng',['集成','继承'])
        # Compile the LM vocabulary head and copied-cache suffix path before
        # the worker reports ready, rather than during the first typed word.
        self.route('I think ','he',['和','喝','何'])
        self.route('这个职位拥有决定预算分配的','quanli',['权力','权利','全力','劝离','圈里','泉里','拳理','全利','全礼','犬吏','全里','全离'])
    @lru_cache(maxsize=32)
    def cap(self,prefix):
        start=0
        while start<len(prefix) and len(self.tok(prefix[start:],add_special_tokens=False).input_ids)>100: start+=1
        return prefix[start:]
    def rank(self,prefix,pinyin,words):
        started=time.perf_counter()
        request=build_request(self.cap(prefix),pinyin,words)
        rec,meta=self.record(self.request_type.model_validate(request))
        enc=self.admit(self.engine,self.tok,rec,truncate=False)
        with self.torch.inference_mode(),self.mx.stream(self.mx.gpu):
            probs=self.engine.probs(enc);self.mx.synchronize()
        answer=self.answers([p.tolist() for p in probs],meta)['candidate']
        choice=answer['choice'];distribution=answer['probabilities']
        order=sorted(range(len(words)),key=lambda i:(-distribution[f'c{i}'],f'c{i}'!=choice))
        keep=choice=='keep'
        return dict(order=list(range(len(words))) if keep else order,selected_index=None if keep else int(choice[1:]),keep=keep,
            request_ms=(time.perf_counter()-started)*1000,context_tokens=len(self.tok(request['state']['prefix'],add_special_tokens=False).input_ids))
    def route(self,prefix,raw,chinese):
        return self.language_router.route(prefix,raw,chinese)
