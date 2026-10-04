"""Natural continuation log-likelihoods on Kev's already loaded backbone.

These scores are sums, not per-token means or calibrated intent probabilities.
Jointly encoding prefix + candidate preserves BPE merges at the text boundary.
Only tokens shared with the independently encoded prefix are omitted as a
candidate-independent constant. No BOS/control token is invented for no context.
"""
import math


class ContinuationScorer:
    def __init__(self, ranker):
        self.ranker = ranker
        self.cached_key = None
        self.cached_prefix = None

    def score(self, prefix, words, use_cache=True):
        ranker = self.ranker
        prefix = ranker.cap(prefix)
        prefix_ids = ranker.tok(prefix, add_special_tokens=False).input_ids
        result = dict(scores=None, context_tokens=len(prefix_ids), cache_hit=False)
        if not prefix.strip() or not prefix_ids or not words or any(not word for word in words):
            return result
        # Duplicate alternatives share exactly the same value and avoid extra
        # branches; indices still refer to the supplied native candidate list.
        unique = list(dict.fromkeys(words))
        sequences = [ranker.tok(prefix + word, add_special_tokens=False).input_ids for word in unique]
        special = set(ranker.tok.all_special_ids)
        if any(special.intersection(ids) for ids in [prefix_ids, *sequences]):
            return result
        if any(not ids for ids in sequences):
            return result
        common = 0
        limit = min(len(prefix_ids), min(map(len, sequences)) - 1)
        while common < limit and all(ids[common] == prefix_ids[common] for ids in sequences):
            common += 1
        if common <= 0:
            return result
        key = tuple(prefix_ids[:common])
        remaining = [ids[common:] for ids in sequences]
        mx = ranker.mx
        lm, text = ranker.engine.lm, ranker.engine.text
        from mlx_lm.models.cache import make_prompt_cache

        def log_probs(hidden):
            head = getattr(lm.language_model, 'lm_head', None)
            logits = head(hidden) if head is not None else text.embed_tokens.as_linear(hidden)
            # FP32 normalization/summation avoids rounding long suffix scores
            # in the backbone's BF16 activation precision.
            logits = logits.astype(mx.float32)
            return logits - mx.logsumexp(logits, axis=-1, keepdims=True)

        with mx.stream(mx.gpu):
            hit = use_cache and key == self.cached_key
            if hit:
                cache, first = self.cached_prefix
            else:
                cache = make_prompt_cache(lm)
                hidden = text(mx.array([key], dtype=mx.int32), cache=cache)
                first = log_probs(hidden[:, -1, :])
                mx.eval(first, [entry.state for entry in cache])
                # A fresh diagnostic pass neither reads nor replaces the cache.
                # Store only after prefill completes, never partial state.
                if use_cache:
                    self.cached_key, self.cached_prefix = key, (cache, first)
            width = max(map(len, remaining))
            if width > 1:
                # Attention and recurrent caches both merge to independent
                # batch rows; suffix evaluation never mutates retained state.
                copied = [type(entry).merge([entry] * len(unique)) for entry in cache]
                ids = mx.array([tokens[:-1] + [ranker.tok.pad_token_id] * (width-len(tokens))
                                for tokens in remaining], dtype=mx.int32)
                tail = log_probs(text(ids, cache=copied))
            values = []
            for i, tokens in enumerate(remaining):
                total = first[0, tokens[0]]
                # Right-padding is after real tokens in a causal model. Read
                # only actual targets: no padding/extra EOS contributes.
                for j in range(1, len(tokens)):
                    total = total + tail[i, j-1, tokens[j]]
                values.append(total)
            values = mx.stack(values)
            mx.eval(values)
            mx.synchronize()
        scores = values.tolist()
        if not all(math.isfinite(value) for value in scores):
            return result
        by_word = dict(zip(unique, scores))
        return dict(result, scores=[by_word[word] for word in words], cache_hit=hit)
