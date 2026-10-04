# Continuation ranking

As of v0.1.9, **Context prediction** is the default. `KevRanker.rank(..., strategy='continuation')` scores the supplied native candidates with the vocabulary head of the **same merged MXFP8 backbone**. The original pointer head remains available as **Kev decision ranking** (`strategy='kev'`). Both use the same downloaded checkpoint, with no additional model or network request. The scoring algorithms and the v0.1.8 measurements below are unchanged by this default switch.

The scorer jointly tokenizes preceding text plus each candidate, intersects those tokens with the independently tokenized capped prefix, and sums the remaining causal log-likelihoods. It includes shared candidate tokens and tokens merged across the BPE boundary. This is a likelihood sum, never a per-token mean. Normalization and sums use FP32 over the backbone's existing activations. Duplicate words share a score; equal scores preserve native order. Invalid/control-token encodings, missing usable context, non-finite scores and all-equal scores preserve the original order with `keep=True`. No BOS or other control token is invented to score empty context.

One exact token-matched prefix is retained. Batch branches copy both attention and recurrent cache state, right-padding contributes no likelihood, and `use_cache=False` neither reads nor replaces the retained prefix. The pointer cache and the unchanged Chinese/English router retain separate state.

These scores are **not calibrated intent probabilities**. Unlike the Kev pointer head, continuation likelihood has no learned `keep` alternative. A high relative likelihood only identifies the best supplied candidate; it cannot establish that any candidate fits. Sum likelihoods can also favor short/common continuations. No threshold was fitted to these diagnostics.

## Frozen fresh evaluation

The 44 cases in [fresh-labels.json](fresh-labels.json) were authored before model scoring. All cases were retained, including missing targets and errors. The frozen label SHA256 is `459f270b621eacaecabd1107349fddc9ed64f45d6c5992b03126c20abe9e253a`, recorded in [fresh-freeze.json](fresh-freeze.json). The freeze was finalized before candidate capture and scoring; labels were not revised after seeing outputs.

The fixture covers short natural context, colloquial chat, longer and capped context, technical/work domains, English/code/names, a legitimate `制定`/`制订` alternative label, unequal candidate lengths, distractors, literal English, no context and deliberately mismatched pinyin with no fitting candidate. It is agent-authored synthetic material, **not a held-out or real-typing evaluation**. Many contexts strongly identify a single final character, so the result should not be generalized to ambiguous daily typing.

[fresh-cases.json](fresh-cases.json) contains actual first-page candidates (maximum 12) from librime 1.17.0 and the packaged, non-learning Wanxiang profile. Capture used fresh sessions in a temporary copy of the deployed profile, no gold-word commits, no personal dictionary, and the production `native/Sources/Coverage.c` coverage calculation. Candidates were not manually selected or rewritten. Six of 40 labeled targets were absent from the eligible first page; those cases remain in the report. Five snapshots have unequal candidate character lengths, including literal-English alternatives; token lengths can differ further.

The evaluator uses production `DecisionService` eligibility (consume at least as much pinyin as candidate zero), native index mapping, single-eligible inference skipping and Chinese/English routing. Each ranking arm uses the identical snapshot. Each eligible snapshot is ranked for this comparison even when routing chooses English; real native input would then bypass Chinese ranking. Ranking accuracy and the effective choice after English routing are both recorded. There are 38 old and 41 fresh diagnostic inference cases left after the English-route bypass. Empty-context and no-fit cases have no target label and are reported separately.

## Results

One run on the development M2 Pro, production MXFP8 weights, with relevant request shapes warmed once. Complete per-case results are in [continuation-results.json](continuation-results.json).

| Diagnostic | Old development set | Fresh frozen set |
| --- | ---: | ---: |
| Total snapshots | 42 | 44 |
| Labeled snapshots | 42 | 40 |
| Labeled target supplied | 40 | 34 |
| Missing target | 2 | 6 |
| Static first candidate accepted | 17 / 42 | 13 / 40 |
| Kev accepted | 32 / 42 | 20 / 40 |
| Continuation accepted | 40 / 42 | 34 / 40 |
| Kev accepted when target supplied | 32 / 40 (80%) | 20 / 34 (58.8%) |
| Continuation accepted when target supplied | 40 / 40 (100%) | 34 / 34 (100%) |
| Eligible diagnostic ranking calls | 38 | 44 |
| Calls remaining after English-route bypass | 38 | 41 |
| Kev fresh / cached median | 159.16 / 113.67 ms | 131.08 / 110.65 ms |
| Continuation fresh / cached median | 73.00 / 31.33 ms | 49.97 / 32.65 ms |
| Cached winning choice or `keep` changes | 0 for both | 0 for both |

The old 42 snapshots were previously used during development and are reported separately. Four have only one eligible candidate and skip model ranking; the timing medians exclude those skips. Fresh timing medians include the two continuation no-context returns. Fresh/cached means a measured uncached prefill pass versus a measured exact-prefix reuse pass after a warm-up; `use_cache=False` leaves the retained cache untouched. This is one sequential benchmark, not a randomized repeated latency study. Timings exclude native debounce, routing, transport, rendering, loading and first-use compilation.

In the fresh set, continuation kept native order on both no-context cases (2/2); Kev kept neither (0/2). The unchanged router treated empty-context `an` as English and `shi` as uncertain, so a ranking fallback does not imply a language-routing fallback. Continuation kept neither deliberate no-fit case (0/2); Kev kept one (1/2). In the equation case, continuation promoted `猫` even though no candidate can complete the equation. In the password case both selected the native first candidate `通`, which also does not fit. These failures make Context prediction materially different from the pointer ranker.

The router matched the authored expectation on 41/44 fresh cases: two specific-name contexts returned uncertain, and empty-context `an` returned English. There were no false-English decisions for authored Chinese contexts. A separate 74-case routing regression preserved every previously recorded decision; 73/74 matched the original fixture labels, with the existing uncertain name case unchanged. Both arms' effective accepted totals after routing matched their ranking totals. These expectations are diagnostic labels, not language-intent ground truth.

## Reproduce

Use the source-build Python environment and the separately installed pinned model. Capture requires the already prepared `.build/rime/dist` and `.build/package-data` inputs; it compiles only a temporary evaluation C bridge and does not change installed Rime data.

```sh
python -m unittest discover -s tests -p 'test_continuation.py'
python -m unittest discover -s tests -p 'test_ranker_evaluation.py'
python scripts/evaluate_rankers.py --capture-only
python scripts/evaluate_rankers.py --output .build/continuation-evaluation.json
python scripts/check_language.py --output .build/continuation-routing-check.json
```

The evaluator rejects a changed frozen-label digest or snapshots inconsistent with the authored labels. It writes only synthetic snapshots/scores; it never reads a draft or changes app preferences. The report's snapshot SHA256 allows the exact candidate capture to be identified. Re-capture may depend on available packaged assets; reproduce the checked-in snapshots for an identical ranking comparison. Exact timings and close scores can vary by hardware and run.
