# Prediction speed and quality

These are synthetic diagnostics on an M2 Pro, not estimates of real typing accuracy. They use the 42 `chinese-regression` snapshots in [the routing fixture](../language-routing/cases.json), with handwritten answer labels in [labels.json](labels.json). There is no personal learning. Only candidates consuming at least as much pinyin as Rime's first candidate are eligible, matching the production coverage rule. Four snapshots have just one eligible candidate and normally skip inference. Forty snapshots contain an accepted answer; two do not. The original cache/quality experiments below used BF16; v0.1.7 switches the app's default backbone weights to MXFP8.

## MXFP8 default

The original adapter is merged before in-memory weight quantization. The pointer head remains FP32; activations and recurrent state keep their existing precision. Linear and embedding layers use MLX's MXFP8 format with groups of 32. Temporary BF16 conversion buffers are cleared before inference caches are constructed. Source model files and checksums remain unchanged; the app does not store an additional converted checkpoint.

| Weight format | Backbone parameter storage | Fresh context median | Cached context median | Kev accepted / 42 | Continuation accepted / 42 |
| --- | ---: | ---: | ---: | ---: | ---: |
| BF16 | 1.505 GB | 133 ms | 91 ms | 32 | 39 |
| MXFP8 | 0.776 GB | 157 ms | 110 ms | 32 | 40 |
| 8-bit affine (diagnostic only) | 0.800 GB | 147 ms | 103 ms | 32 | 40 |

All Kev word choices and `keep` decisions matched BF16 across the 42 original snapshots. The extra accepted continuation was `权力` instead of `权利`; one changed answer on a development fixture is not evidence of general quality improvement. Weight storage excludes activations, caches, allocator buffers, head and runtime. Timings are one run with relevant shapes warmed first; MXFP8 saves memory but was slower for pointer ranking on this Mac. It is the production default because of the memory preference. Loading/conversion still briefly requires the original BF16 weights.

The production MXFP8 loader also preserved all 74 Chinese/English routing decisions. Its expanded cache check preserved original-order choices and the nine-step edit probe. Two of 114 candidate-order comparisons changed the `keep` decision on reversed lists; two of 40 extra matrix pairs changed choice, including one `keep` flip. Their reference winner margins were .0011, .0060, .0004 and .0045. Maximum rounded probability drift was .0157. The MXFP8 diagnostic uses an empirical .020 numerical budget, requires original-order/edit choices to stay unchanged, and permits reordered/extra choice flips only when the original selection gap is at most .010 and both selections remain inside the numerical near-tie band. These bounds are diagnostic budgets, not universal accuracy guarantees. All flips, including `keep`, are reported explicitly.

Use `--quantization bf16` on the diagnostic scripts below to reproduce the original precision. Omitting it uses the production MXFP8 default.

## Reusing preceding context

The full English prompt, 100-token context limit, supplied candidates and checkpoint remain fixed. The original scorer prefills the whole state on each request. The new scorer retains one token-matched preceding-text prefix, then scores changed pinyin/candidates on a copied KV/DeltaNet cache. Token boundaries are checked against the actual record rather than assuming independently tokenized strings concatenate exactly.

| Worker path | Correct / 42 | Median model request |
| --- | ---: | ---: |
| Original full prompt | 32 | 135 ms |
| Full prompt, fresh cached context | 32 | 134 ms |
| Full prompt, reused context | 32 | 91 ms |
| Short prompt, reused context (experiment only) | 30 | 69 ms |

The shorter prompt is excluded from the app because two accepted answers were lost. The winning choice/keep decision matched on all 42 full-prompt cases. Two lower-ranked alternatives changed order; probabilities are not bitwise identical.

Expanded BF16 validation compared the original and cached scorers on 114 original/reversed/rotated candidate lists: zero winner changes, median 134 ms versus 93 ms. Forty additional pairs cover 1/2/7/12 alternatives, changed candidate text, empty/newline/emoji/control-token-looking user context, and the ten closest original margins. One unusual near-tie changed winner: reference probabilities .3592/.3578 became .3510/.3625. Maximum probability change across the extra matrix was .0100, versus .0089 on the normal comparisons. These values come from the official four-decimal answer conversion. The pinned [upstream MLX implementation](https://github.com/jaredpalmer/kev/blob/84847f0a883d900f7de5b7a57eaa341ca7f9a6b4/kev/mlx_model.py) documents BF16 split-pass differences of about .01. BF16 validation retains its .011 numerical budget and unchanged ordinary choices; extra-matrix flips must have an original selection gap at most .010 and stay within the numerical near-tie band. It does not claim universal winner equivalence.

A separate nine-step raw-letter/backspace probe, with frozen alternatives, had eight cache hits and no winner changes. That probe checks state reuse; it does not simulate live Rime candidate generation. Six unit tests cover token-boundary mismatches, changed context, copied-state isolation, failed prefill, empty prefixes and state-token limits.

These timings exclude the native 85 ms ranking debounce, language check, transport and UI. A new preceding context still needs prefill. Native candidates remain available asynchronously. Only one context cache is retained in memory; no user text is logged or saved.

## Quality diagnostics

| Ranking strategy | Accepted answers / 42 |
| --- | ---: |
| First static Rime/Wanxiang candidate | 17 |
| Kev pointer head, full prompt | 32 |
| Same pointer scores, ignoring `keep` (diagnostic only) | 36 |
| Natural continuation likelihood, same merged backbone (diagnostic only) | 39 |

The continuation experiment scores the supplied Chinese alternatives after the same capped preceding text, using the loaded model's vocabulary head rather than its decision pointer head. It uses the natural-language calculation already used for Chinese/English routing, with fresh context per case. Its median was 77 ms versus 133 ms for pointer decisions in the same run. It needs no additional model or download. It is an offline experiment and is **not enabled in the app**.

Two missing-target cases (`失事` and the specific name `李薇`) need better candidate retrieval; a ranker cannot select a word it never receives. Of the eight other strict-label Kev misses, two choices are plausible alternatives (`制订` and `像似`). Several clear misses come from `keep` winning despite a plausible correct option: `权力`, `反映`, `包袱`, `知识`. Ignoring `keep` improves those four on this fixture, but could promote unsuitable words when no candidate fits. Continuation scoring gets all supplied targets except the `权力`/`权利` distinction, but still fails both missing-target cases.

These cases have already been used for development and are not a held-out quality evaluation. Before changing production ranking, compare continuation scoring and the pointer head on fresh examples: ordinary short context, longer phrases, editing, mixed English/code/names, ambiguous input and cases where none of the candidates fits. Sum likelihoods can favor shorter or common phrases, and are not calibrated probabilities of intention. Candidate retrieval and typo tolerance need their own coverage measurements. Larger models or IME-specific training are possible later; this result makes the existing backbone a useful first experiment.

## Reproduce

Use the source-build Python environment and separately installed pinned model:

```bash
python -m unittest discover -s tests
python scripts/check_ranking_cache.py --output .build/cache-check.json
python scripts/compare_rankers.py --output .build/ranker-comparison.json
python scripts/compare_rankers.py --quantization bf16 --output .build/bf16-comparison.json
```

The scripts accept `--model-dir`. `compare_rankers.py` additionally accepts `--cases` and `--labels` for fresh fixtures. It emits synthetic inputs/scores to the requested report; it does not capture typing, alter preferences or replace the installed app. Exact timings and close choices can vary across hardware and runs.
