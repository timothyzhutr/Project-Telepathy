# Automatic language routing

The pointer head's generic language questions showed strong option-order bias in exploratory checks. Auto mode therefore uses the **same already loaded, LoRA-merged Kev/Qwen backbone** to score natural continuations: preceding text plus literal keyboard input, versus preceding text plus each fully covered Chinese candidate. Candidate ranking still uses Kev's existing pointer head and unchanged ranking prompt.

Scores sum autoregressive log-likelihoods over the suffix after the alternatives' longest common token prefix. Branch caches are copied from one exact-prefix cache; a different token prefix invalidates that cache. Chinese suffixes containing ASCII letters are excluded from this comparison. Duplicates are removed. At least 97% of the normalized alternative weight selects English, at most 3% selects Chinese, and the middle range is uncertain. These are conservative implementation thresholds, **not calibrated probabilities of human intent**. Total sequence likelihood has length/tokenization biases and can miss names, code-switching, or uncommon words.

The native IME starts this check immediately, then schedules Chinese pointer ranking at the existing 85 ms deadline after a Chinese/uncertain result. A slower result can delay ranking, but native Rime candidates and key handling never wait for it. English bypasses pointer ranking. A fresh snapshot revision, manual choices, commit, and deactivation guard against stale responses.

## Reproduce

With the source dependencies and separately installed pinned model:

```bash
python scripts/check_language.py --output .build/language-results.json
```

`cases.json` contains 74 **handcrafted synthetic** snapshots captured from the packaged Wanxiang profile with learning disabled: 24 matched English/Chinese contexts sharing the same letters, 42 earlier Chinese regression cases with longer passages, and 8 mixed-language cases. Candidate text and consumed-input endpoints are frozen to make scoring reproducible. No personal writing is included. The script also verifies that reuse of a cached prefix agrees with fresh evaluation and that original pointer ranking still selects 权利 in the existing smoke case.

On the development M2 Pro, this exploratory set produced:

| Group | Matching label | Chinese wrongly routed to English | Median inference |
|---|---:|---:|---:|
| Matched contexts | 24/24 | 0 | 64 ms |
| Chinese regressions | 41/42; one uncertain | 0 | 75 ms |
| Mixed language | 8/8 | 0 | 0 ms |

Five mixed examples had only exact literal-English full candidates, allowing the service to skip neural inference; the Chinese mixed examples used the model. An additional short/long version of the 24 paired examples matched 48/48 at 63/75 ms median; those longer passages explicitly described their language and are an easier diagnostic, not independent accuracy evidence. A same-context `c → ca → can` cache trace took approximately 64 → 35 → 36 ms. Those diagnostic traces used fixed Chinese alternatives rather than freshly captured candidates at every letter.

These are development checks, not a held-out typing benchmark. Threshold selection and implementation exploration used these examples. They do not estimate real accuracy, end-to-end key latency, battery consumption, or every application's context-access behavior. Real typing should test contractions, punctuation, short-word boundaries, very fast typing, and frequent language switches.
