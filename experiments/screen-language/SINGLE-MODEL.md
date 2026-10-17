# One model for typing and an initial screenshot hint

Measured on an Apple M2 Pro with 16 GiB RAM, macOS 27.0.1, 2026-10-17. This is an isolated research result; the installed Telepathy app has not been changed.

**A single vision-capable Qwen3.5-0.8B checkpoint can preserve the current continuation ranker's measured quality and also read an initial screenshot.** It is worth trying as an optional starting-language hint. Screenshot results have enough mistakes and option-order sensitivity that they should yield to manual selection and subsequent text context.

## What was tested

The existing Kev reference ran first and exited. Each subsequent research process loaded exactly one full Qwen vision-language model. Its text backbone served Telepathy's existing continuation-likelihood scorer and language router; its vision path answered the starting-language question. These are views of the same loaded weights, not separate text and vision models.

The candidate was [mlx-community/Qwen3.5-0.8B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-0.8B-MLX-4bit), revision `5d894f8cc4ef3e6c88537bf3746ed262f549da6a`, a quantization of Qwen3.5-0.8B. It uses 4-bit affine weight quantization with group size 64 and retains a vision tower. It is **not Kev with image input added**. The reference uses Qwen3.5-0.8B-Base with Kev's merged LoRA and MXFP8 quantization. Checkpoint, training and precision all differ, so this is a practical system comparison rather than an ablation of any one factor.

All screenshots were generated fixtures with an empty, blue-outlined input field. No personal desktop contents were captured. The screenshot question, fixed before the supplemental run, was:

> 蓝色输入框上方的当前对话或正文主要使用哪种语言？忽略菜单和侧栏。

The readout normalizes the next-token logits for `A` and `B`, mapped to Chinese and English. No reply or explanatory text is generated. Images are 864 × 576, approximately 486 visual tokens. This follows OpenJev's option-label decision pattern but uses MLX-VLM instead of its llama.cpp service so that our existing likelihood scorer can use the very same model.

## Word ranking and text routing

Frozen native Rime candidate lists and labels were reused without learning, recapture or label changes. The production scorer caps preceding context at 100 tokens. Each list contains up to 12 native candidates; shorter partial conversions are excluded from the reranking group using the production coverage rule. Empty context and a single eligible candidate retain their normal handling.

| Check | Current Kev continuation scorer | One vision-capable model |
|---|---:|---:|
| Old set, accepted first choice | 40/42 | 40/42 |
| Newer set, accepted first choice | 34/40 | 34/40 |
| Text-language routing | 73/74 | 74/74 |
| Chinese cases incorrectly routed to English | 0 | 0 |
| First-choice changes from using the text cache | 0 | 0 |
| Old set, median fresh / cached ranking | 70.5 / 30.8 ms | 69.1 / 32.7 ms |
| Newer set, median fresh / cached ranking | 47.4 / 31.1 ms | 50.1 / 32.3 ms |

Two old targets and six newer targets are absent from the eligible candidate lists. Both models match all labels where an accepted target is supplied. Equal totals do not mean every selected word is identical, and these small synthetic sets do not establish broad real-world parity.

As a diagnostic, the same vision model was also asked to select a word through an OpenJev-style option-label prompt. This performed worse:

| Set | Original option order | Reversed option order |
|---|---:|---:|
| Old | 31/42 | 21/42 |
| Newer | 19/40 | 8/40 |

The diagnostic used a fixed Chinese question, up to 100 preceding tokens, the pending pinyin and the same eligible candidates. There is no `keep` option. This is not a trained Kev decision head or a claim about every possible OpenJev prompt. **Keep continuation likelihoods for word ranking.**

## Screenshot quality and latency

The original 16 labelled scenes matched 15/16 with Chinese first and 16/16 with English first. The single failure was a short Chinese chat next to a longer English sidebar.

A new set of 24 labelled scenes and four unlabelled controls was frozen before a supplemental run. It includes opposite-language interfaces, unrelated sidebar conversations, English technical terms in Chinese, Chinese names in English, traditional Chinese, short replies and quoted language instructions. Each scene was rendered in light and dark themes and evaluated in both option orders, without retuning the prompt.

| New set | Chinese first | English first | Decisions changed by reversing options |
|---|---:|---:|---:|
| Light theme | 21/24 | 22/24 | 3/24 |
| Dark theme | 23/24 | 21/24 | 2/24 |

That is **87/96 labelled decisions**, with correlated repetitions of 24 scenes, not 96 independent examples. Mixed-language passages, short text and quoted instructions account for the errors. The unlabelled blank, numeric and bilingual controls sometimes produce strong English preferences despite a lack of usable evidence. The option probabilities are not calibrated confidence in the intended language.

Median screenshot requests were about **425–444 ms** across the original and new groups. These warm in-process times include image preparation and inference, but exclude native screen capture, IPC, focus detection, key handling and debounce. Cold model loading took about **4.2 seconds** in the main candidate run.

A single serial worker can make a word-ranking request wait behind a roughly 0.4-second image pass. Asynchronous UI alone does not remove that queue delay. A prototype should start the screenshot pass on focus where possible, keep ordinary native candidates responsive, and disregard results superseded by manual selection or newer text context. No screenshot is needed per word.

The subsequent [native activation timing probe](../activation-timing/README.md) observed 116–2,242 ms between activation and the first key across 11 Codex, TextEdit and Firefox interactions. This confirms an opportunity to start inference earlier, without establishing complete focus coverage or end-to-end latency.

## State and memory

- All 40 original and 112 supplemental image requests left the retained text-prefix cache unchanged.
- A separate 12-request interleaving probe compared both **fresh and cached** scores before and after images, with short Chinese, a longer Chinese prefix and English. Every score delta was zero in that probe.
- Across 80 eligible ranking cases, batched continuation scores and full unbatched teacher-forced scores selected the same first word. One of three numerical spotchecks exceeded the original 0.1 log-probability tolerance: its maximum difference was 0.1352. Thus winner agreement passed; strict numerical parity did not.
- Candidate weight arrays occupy **625 MB**; the verified checkpoint/tokenizer/processor download is **652 MB**. Runtime and temporary tensors are additional.
- A separate normal-workload probe, without the expensive full-vocabulary reference arm, measured macOS `vmmap` physical footprint of **1.3G after typing and after image processing**, with an observed **2.3G peak**. Peak MLX allocation was **1.73 GB**. RSS, physical footprint and MLX allocations are different measurements and must not be added together.

This is feasible on the tested 16 GiB Mac, but around 1.3G of process footprint is a material cost for an input method. More work would be needed before claiming a small idle footprint, low battery impact or a reliable first-keystroke deadline.

## Reproduce and inspect

[`single-model-results.json`](single-model-results.json) includes source revisions, checksums, dependency versions, per-case outputs, timing summaries, state checks and resource snapshots. The earlier llama.cpp experiment remains in [`README.md`](README.md) and [`results.json`](results.json).

Use an isolated Python 3.12 environment with the versions in the report. The research environment reused existing MLX/MLX-LM/Transformers/Torch dependencies read-only and added `mlx-vlm==0.7.8`, `pillow==12.3.0` and `torchvision==0.23.0`. Unused MLX-VLM audio/server extras were not installed. The experiment does not change the installed helper's environment.

Download the pinned candidate metadata and checkpoint, excluding unrelated repository files:

```bash
hf download mlx-community/Qwen3.5-0.8B-MLX-4bit \
  --revision 5d894f8cc4ef3e6c88537bf3746ed262f549da6a \
  --include model.safetensors model.safetensors.index.json config.json \
    tokenizer.json tokenizer_config.json vocab.json chat_template.jinja \
    preprocessor_config.json processor_config.json video_preprocessor_config.json \
  --local-dir .runtime/single-model/qwen-mlx
```

The safetensors file must have SHA-256 `f5a0d9dd3efa73510542a8023d610ff26be2b4b020d181cfc4bedaa1fcc5dd9e`; checksums for every downloaded file are recorded in the report. Downloaded weights stay outside Git.

Run each command **sequentially**, substituting the Python path for the isolated environment:

```bash
# Kev baseline: use the existing Kev environment and installed model files.
.runtime/kev/venv/bin/python experiments/screen-language/lease_exec.py \
  --record .runtime/single-model/kev-lease.json -- \
  .runtime/kev/venv/bin/python experiments/screen-language/shared_ranking.py \
  --kind kev --output .runtime/single-model/kev-reference.json

# Full vision model: existing continuation scorer, router, and screenshot readout.
.runtime/single-model/venv/bin/python experiments/screen-language/lease_exec.py \
  --record .runtime/single-model/vision-lease.json -- \
  .runtime/single-model/venv/bin/python experiments/screen-language/shared_ranking.py \
  --kind vision --model .runtime/single-model/qwen-mlx --with-images \
  --output .runtime/single-model/vision-shared.json
```

The supplemental runner `shared_supplement.py`, state probe `state_probe.py` and resource probe `resource_probe.py` accept the same `--model` and `--output` arguments. Run each through `lease_exec.py` with a separate `--record` file.

The lease parent loads no model. It holds Telepathy's production singleton lock until the research child exits, preventing an installed helper from loading alongside it. If the installed helper was running beforehand, the wrapper stops and restores it without changing preferences. All five recorded runs exited before releasing the lock. The installed helper was not running at their start and was left in that state.

Credits: [Qwen3.5](https://github.com/QwenLM/Qwen3.5) and its MLX community conversion, [MLX](https://github.com/ml-explore/mlx), [MLX-LM](https://github.com/ml-explore/mlx-lm), [MLX-VLM](https://github.com/Blaizzy/mlx-vlm), [OpenJev Multimodal](https://github.com/jev-skills/openjev-multimodal), and the existing Kev/Rime/Wanxiang components credited by the main repository. No third-party model weights are included in these experiment files.
