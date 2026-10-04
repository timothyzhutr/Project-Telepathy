"""A single copied prefix; context equality is checked against actual encoded tokens."""
class RankingCache:
    def __init__(self, prefill, branch, copy):
        self.prefill,self.branch,self.copy=prefill,branch,copy
        self.key=None
        self.prefix=None
        self.hit=False
    def score(self, encoded, stable_tokens):
        ids=encoded['ids']
        limit=min(len(stable_tokens),len(ids),encoded.get('state_tokens',len(ids)))
        common=0
        while common<limit and stable_tokens[common]==ids[common]:common+=1
        key=tuple(ids[:common])
        self.hit=key==self.key
        if not self.hit:
            prefix=self.prefill(key)
            self.key,self.prefix=key,prefix
        return self.branch(encoded,self.copy(self.prefix))
