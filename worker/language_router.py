"""Contextual literal-English vs Hanzi scoring with the already loaded backbone.

Scores are normalized likelihoods of the supplied continuations, not calibrated
probabilities of a person's intent. Only a large margin changes the input mode.
"""
import math,time

class LanguageRouter:
    def __init__(self,ranker):
        self.ranker=ranker

    def route(self,prefix,raw,chinese):
        started=time.perf_counter()
        scored=self.ranker.continuation_scorer.score(prefix,chinese+[raw])
        scores=scored['scores']
        if not scores or not all(math.isfinite(value) for value in scores):
            return dict(language='uncertain',request_ms=0)
        maximum=max(scores)
        weights=[math.exp(v-maximum) for v in scores]
        english=weights[-1]/sum(weights)
        if not math.isfinite(english):return dict(language='uncertain',request_ms=0)
        language='english' if english>=.97 else 'chinese' if english<=.03 else 'uncertain'
        return dict(language=language,english_score=english,
                    request_ms=(time.perf_counter()-started)*1000)
