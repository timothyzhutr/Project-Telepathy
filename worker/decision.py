"""Rank copied native snapshots; Rime owns composition and selection."""
import threading
class DecisionService:
    def __init__(self,ranker=None):
        self.ranker=ranker
        self.lock=threading.Lock()
    @staticmethod
    def snapshot(body):
        if not isinstance(body,dict): raise ValueError('Expected an object')
        revision=body.get('revision');prefix=body.get('prefix');raw=body.get('pinyin')
        pending=body.get('pending',raw);words=body.get('candidates');ends=body.get('candidate_ends')
        strategy=body.get('strategy','continuation')
        alphabet="abcdefghijklmnopqrstuvwxyz'"
        if (not isinstance(strategy,str) or strategy not in ('kev','continuation') or
            type(revision) is not int or revision<0 or
            not isinstance(prefix,str) or len(prefix)>512 or '\x00' in prefix or
            any(not isinstance(p,str) or not 0<len(p)<=64 or any(c not in alphabet for c in p) for p in (raw,pending)) or
            not isinstance(words,list) or not 1<=len(words)<=12 or
            any(not isinstance(w,str) or not 0<len(w)<=128 or '\x00' in w for w in words) or
            not isinstance(ends,list) or len(ends)!=len(words) or
            any(type(e) is not int or not -1<=e<=len(raw.encode()) for e in ends)):
            raise ValueError('Invalid native snapshot')
        return revision,prefix,raw,pending,words,ends
    def language(self,body):
        revision,prefix,raw,pending,words,ends=self.snapshot(body)
        fallback=dict(status='ok',revision=revision,language='uncertain',request_ms=0)
        if raw!=pending or any(e<=0 for e in ends):return fallback
        full=[w for w,e in zip(words,ends) if e==len(raw.encode())]
        chinese=list(dict.fromkeys(w for w in full if not any(c.isascii() and c.isalpha() for c in w)))
        if not chinese:
            if any(w.lower()==raw.lower() and w.isascii() for w in full):
                return dict(fallback,language='english',english_score=1)
            return fallback
        with self.lock:
            if self.ranker is None:return fallback
            try:
                result=self.ranker.route(prefix,raw,chinese)
                if result.get('language') not in ('english','chinese','uncertain'):return fallback
                return dict(result,status='ok',revision=revision)
            except Exception:return fallback
    def decision(self,body):
        revision,prefix,raw,pending,words,ends=self.snapshot(body)
        original=list(range(len(words)))
        unavailable=dict(status='unavailable',revision=revision,order=original,inferred=False,inferred_indices=[])
        if any(e<=0 for e in ends): return unavailable
        eligible=[i for i,e in enumerate(ends) if e>=ends[0]]
        shorter=[i for i in original if i not in eligible]
        if len(eligible)==1:
            return dict(status='ok',revision=revision,order=eligible+shorter,selected_index=None,keep=True,ranked=False,inferred=False,inferred_indices=[],request_ms=0)
        with self.lock:
            if self.ranker is None: return unavailable
            try:
                strategy=body.get('strategy','continuation')
                result=self.ranker.rank(prefix,pending,[words[i] for i in eligible],strategy=strategy)
                if sorted(result['order']) != list(range(len(eligible))): return unavailable
                selected=result.get('selected_index')
                return dict(result,status='ok',revision=revision,ranked=True,strategy=strategy,
                    inferred_indices=eligible if result.get('inferred') is True else [],
                    order=[eligible[i] for i in result['order']]+shorter,
                    selected_index=eligible[selected] if selected is not None else None)
            except Exception: return unavailable
