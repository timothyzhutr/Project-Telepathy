# Screenshot starting-language prior

Local OpenJev Multimodal test on an Apple M2 Pro, 16 GiB RAM, 2026-10-17.

**Follow-up:** the [single-model comparison](SINGLE-MODEL.md) tests one vision-capable model for both the existing typing scorer and the screenshot hint, with additional frozen scenes and memory/state checks. The results below describe the earlier standalone llama.cpp experiment.

The intended behavior is small: **one initial screenshot biases the first words toward Chinese or English; Telepathy's existing text-context routing then takes over.** The screenshot is not used to rank words, generate replies, or continually decide the language during typing. This experiment does not modify the installed IME.

## Result

The simple binary task performed substantially better than the earlier, broader routing question. With an empty input field and a short Chinese question, the full-detail configuration matched all 16 labelled synthetic scenes in both option orders. That makes it a candidate for an optional starting hint, subject to real typing tests.

| Image-token budget | Labels matched, Chinese/English order | Labels matched, reversed order | Changed decisions after reversal | Median fresh request |
|---|---:|---:|---:|---:|
| 512 | 16/16 | 16/16 | 0/16 | 465 ms |
| 256 | 15/16 | 13/16 | 2/16 | 269 ms |
| 128 | 13/16 | 14/16 | 3/16 | 180 ms |

Latency medians above include all requests at that image budget, including four unlabelled controls. The 512-token run includes both short English and Chinese prompts; the smaller budgets use the Chinese prompt. With the English prompt at 512 tokens, both option orders matched 15/16 labels, consistently misclassifying an English paragraph containing Chinese project names. The Chinese prompt handled that example at full detail. Smaller images also missed mixed-language and conflicting-interface examples.

These are **16 handcrafted labelled scenes, not a 100% real-world accuracy claim**. Four blank/numeric/bilingual scenes are unscored because either starting language can be reasonable. They are recorded to show the model's bias when relevant evidence is absent. Repeated option orders do not increase the independent sample count. Prompt and resolution comparisons reuse the same scenes after the user clarified the intended scope; this is an exploratory diagnostic, not held-out validation or a calibrated estimate of user intent.

Every initial-prior request reported zero reused prompt tokens. Times include localhost HTTP, image decoding/resizing, vision processing, prompt processing, and the single-token readout. They exclude screen capture, fixture rendering, base64 preparation, model startup, native key handling and debounce. An actual focus-to-first-word benefit has not yet been measured. Other desktop applications remained running.

## Exact input

The screenshot shows a conversation/document, an empty blue-outlined input field, and sometimes a sidebar in the opposite language. No preceding text or typed letters are supplied. State contains only an observation identifier and `Before typing into the blue input box.`

Chinese question:

> 蓝色输入框上方的当前对话或正文主要使用哪种语言？忽略菜单和侧栏。

Choices are `chinese: 中文` and `english: 英文`. The English variant asks which language the conversation/document mainly uses and tells the model to ignore menus and sidebars. The wrapper reads one option-label token and returns the two normalized probabilities. They are not calibrated correctness probabilities.

For a prototype, this result would be a weak initial bias. Begin capture on input activation where possible, keep key handling asynchronous, and let manual language selection or a newer text-context decision supersede it. A late screenshot reply must not change committed text or override newer context. No screenshot request is needed for each word.

## Runtime and memory

- [OpenJev Multimodal](https://github.com/jev-skills/openjev-multimodal), commit `c23bba19751a7b3008c58a86f77f2cc2129357fc`; MIT code.
- Qwen3.5-0.8B `Q4_K_M`, matching F16 vision projector, pinned Unsloth revision `6ab461498e2023f6e3c1baea90a8f0fe38ab64d0`; Apache-2.0 weights.
- Official llama.cpp macOS arm64 release `b9670`, commit `02810c7aa`, using Metal, four CPU threads and a 4,096-token context.
- Weight download: 532,517,120-byte text model plus 204,987,232-byte projector, **737.5 MB total**. Runtime, activations and caches are additional.
- The default llama.cpp prompt-history cache was configured for 8 GiB. After the initial broader runs and basic vision controls, `vmmap` reported the worker's physical footprint as **9.3G**, despite much lower resident RSS. That default is unsuitable for this IME workload.
- Adding `--cache-ram 0` bounded the separate test worker. A full-detail rerun measured **1.16 GB peak combined process RSS** for the API and its owned inference child. A later snapshot reported worker/API physical footprints of `474.9M`/`68.5M`. RSS and physical footprint measure different things; do not add them or equate either with all system memory costs. This is additional to Telepathy's existing Kev helper.

The extra model was stopped after testing. The 737.5 MB of verified weights remain in the isolated research cache for reproduction; no weights are included here.

## Reproduce

Use Python 3.11 or later on Apple Silicon. Install the pinned upstream checkout into an isolated environment:

```bash
git clone https://github.com/jev-skills/openjev-multimodal.git .runtime/openjev-multimodal/upstream
git -C .runtime/openjev-multimodal/upstream checkout c23bba19751a7b3008c58a86f77f2cc2129357fc
python3 -m venv .runtime/openjev-multimodal/venv
.runtime/openjev-multimodal/venv/bin/python -m pip install -e .runtime/openjev-multimodal/upstream psutil
HF_HOME="$PWD/.runtime/openjev-multimodal/hf" HF_TOKEN= \
  .runtime/openjev-multimodal/venv/bin/openjev download --profile fast
```

Download the official [macOS arm64 b9670 archive](https://github.com/ggml-org/llama.cpp/releases/download/b9670/llama-b9670-bin-macos-arm64.tar.gz), verify SHA-256 `67f8a8c6710dc81524ef7b102f295cbf19e880bf3822030420a0eeeeab2148b2`, and extract its `llama-b9670` directory into `.runtime/openjev-multimodal/llama/`.

Start the bounded service in one terminal:

```bash
chmod +x experiments/screen-language/llama-bounded.sh
TELEPATHY_LLAMA_SERVER="$PWD/.runtime/openjev-multimodal/llama/llama-b9670/llama-server" \
HF_HOME="$PWD/.runtime/openjev-multimodal/hf" HF_TOKEN= \
  .runtime/openjev-multimodal/venv/bin/openjev serve --profile fast \
  --port 19876 --backend-port 19877 --context 4096 --image-tokens 512 --threads 4 \
  --llama-server experiments/screen-language/llama-bounded.sh
```

After the service reports ready, run in another terminal:

```bash
.runtime/openjev-multimodal/venv/bin/python experiments/screen-language/prior_probe.py \
  --output .runtime/openjev-multimodal/reproduce-prior --image-tokens 512
```

For the smaller budgets, restart the service with `--image-tokens 256` or `128`, pass the same value to the probe, and add `--styles chinese`. Stop the service with Ctrl+C. The probe renders original synthetic fixtures using macOS's STHeiti font; it never captures a personal screen.

## Evidence and earlier scope

[`prior-cases.json`](prior-cases.json), [`prior_probe.py`](prior_probe.py), and [`results.json`](results.json) contain the narrowed dataset, runner and measured summaries, including exact source/model digests. Local raw request receipts, checksummed fixtures, dependency lock, logs and memory snapshots are under `.runtime/openjev-multimodal/` and are not packaged.

The initial broader diagnostic asked for a three-way Chinese/English/uncertain typing decision, supplied the first unconverted letters, and included explicit output-language instructions. It matched 12/28 labels in its initial option order; all 28 decisions changed under at least one option rotation. Shorter prompt variants matched 16–22/28 depending on language and order. Those results motivated the narrower test after the user clarified that only a starting prior was wanted. They do not describe the simpler binary task above.

The broader default-cache run measured 512 ms median for a fresh full-detail image, versus 34 ms for an **identical repeated request**. The bounded rerun measured 512/36 ms respectively. Those cache-hit numbers do not describe a new screenshot. Plain Chinese/English transcription controls confirmed that image input and text recognition worked. Three harness checks verify probability validation and that failed requests cannot inflate quality counts.
