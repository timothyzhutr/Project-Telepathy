# Using Telepathy

[Back to the README](../README.md)

## Installation

**Apple Silicon, macOS 26.2 or later.** This release bundles the executable, Python runtime and inference libraries. Homebrew, Python and an API key are not needed.

1. Download the ZIP from [Releases](https://github.com/timothyzhutr/Project-Telepathy/releases/latest) and extract it.
2. Run `Install Telepathy.command`, keeping it beside `Telepathy.app`. It installs into your own `~/Library/Input Methods` directory, and preserves an existing Telepathy app/profile in `~/Library/Application Support/Telepathy/InstallBackups`.
3. Add **Telepathy** in System Settings → Keyboard → Text Input → Edit → **+**. Select it from the input-source menu. If macOS has not discovered it yet, log out and back in.
4. Download the separately distributed Kev adapter and Qwen base model with `Download Kev Model.command`, or run:

```bash
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --download-model
```

The explicit setup command downloads only required files at pinned revisions, verifies SHA-256 checksums, and stores them in `~/Library/Application Support/Telepathy/models`. Allow approximately **1.8 GB** for weights, in addition to the app. It does not use saved Hugging Face credentials. Subsequent inference runs offline. Native pinyin typing remains available while the model is missing, loading or unavailable.

Telepathy is ad-hoc signed, **not Apple-notarized**. macOS may block a downloaded app or command the first time; use System Settings → Privacy & Security → Open Anyway for the downloaded Telepathy package. A managed Mac may require administrator approval. The installer does not disable Gatekeeper.

## Typing and settings

Type pinyin normally. Space chooses the highlighted candidate; number keys and the native candidate panel select words. Kev ranks up to 12 candidates on the current page. Candidates consuming less input than Rime's first candidate stay behind that group. Manual navigation freezes the current list until the input changes.

The input-source menu includes **Kev assistance**, which switches ranking on/off. Rime's statistical grammar continues to work when Kev assistance is off. No personal dictionary learning is enabled. No typed text is written to the worker log or sent to a cloud API. In applications that do not expose preceding text, the IME uses limited text committed during the current session; contextual quality can be lower.

**Settings…** opens Telepathy's native settings panel above the app you're typing in. Close it with the window button or ⌘W. Preferences save automatically and apply to the candidate panel:

- Candidates per row: automatic, 1, 2, 3, 4, 6 or 12. All 12 candidates remain available; long phrases can wrap.
- Text size (12–28 pt) and appearance (follow system, light or dark).
- Inline pinyin, candidate annotations, Kev timing and the Chinese / English menu-bar status icon.
- Kev assistance and Chinese punctuation.
- Ranking method: **Kev (default)** or **Context prediction (experimental)**. Both use the same local model and download. Context prediction ranks natural continuations of your preceding text; it can be faster but lacks Kev's explicit “keep the original order” decision when every supplied candidate is unsuitable. With no usable context it retains Rime's order. A `Context … ms` annotation identifies this method when timing is enabled; `Kev … ms` identifies the pointer ranker. Scores are not probabilities of your intent. See [the fresh comparison](../experiments/prediction/continuation.md) for synthetic results and limitations.
- Automatic Chinese / English typing (experimental, off by default).
- Automatic punctuation forms in Auto mode (on by default): Chinese or ASCII forms of the mark you press.
- Local model status, model folder access, and an explicit download / repair action. Valid pinned files are reused; missing or damaged files are fetched and verified before the worker reloads them.

Turning assistance off stops the model helper, releasing its model, caches and inference runtime. Turning it on starts the helper again; ordinary Rime typing stays available while the model reloads. Model files remain on disk. Settings survive app updates. **Restore default settings** resets only Telepathy's controls, preserving model files and unrelated preferences.

Enable **Automatic Chinese / English (experimental)** in Settings while Kev assistance is on. Telepathy compares literal keyboard text with complete Chinese candidates using up to 100 tokens of preceding text. Confident English stays literal and Space adds a space; Chinese and uncertain input keep the candidate workflow. Press **↓ or Tab** to restore Chinese choices for the current word. **Shift + a letter** starts literal English until the next space. Caps Lock remains a manual English switch. Auto mode changes Shift's usual Rime language-toggle behavior.

**Automatic punctuation in Auto mode** chooses Chinese or ASCII forms from the current sentence: `这个项目叫 Telepathy，` and `I like 中文.`. It handles commas, periods, question/exclamation marks, colons, semicolons, quotes and brackets, including matching pasted opening marks. It keeps decimal/time separators, URLs, email and backtick code ASCII; pinyin apostrophes remain syllable separators during Chinese composition. An active word commits in its currently displayed language before the mark is inserted. This is a bounded native heuristic over the preceding 512 characters, with **no additional model request or wait**. It chooses the form of your key, not which punctuation mark to write. Mixed-language sentences and context unavailable from the host can still be ambiguous. Disable this setting to return to Rime's configured forms; disable **Use Chinese punctuation** to always use ASCII forms.

The language check uses the already loaded Kev backbone, with no additional model or download. It runs asynchronously before candidate ranking, during its existing debounce whenever possible. English skips pointer reranking; Chinese ranking starts at the original deadline or when a slower language check finishes. Decisions apply only to the current uncommitted snapshot. Very fast typing can outrun a decision, and short words with little context can remain ambiguous; Space uses the state visible at that instant. Auto mode is experimental; its scores are not calibrated probabilities of intent. See [the routing experiment](https://github.com/timothyzhutr/Project-Telepathy/blob/main/experiments/language-routing/README.md) for reproducible synthetic checks and limitations.

**Credits and licenses…** opens the same window on Credits. The Credits tab lists the projects used; the Licenses tab lets you browse their bundled license texts. These tabs work offline. The same texts are included under `Contents/Resources/licenses/`.

Kev's backbone runs on the Apple GPU through MLX with **MXFP8 weight quantization by default**; its small pointer head stays FP32 on the CPU through PyTorch. On the development M2 Pro, backbone weight storage falls from **1.50 GB to 0.78 GB**. Activations, normalization, recurrent state, inference caches and runtime memory are additional, so this does not halve total worker memory. The helper stays resident while assistance is enabled. Decisions are asynchronous, so native candidates appear without waiting for inference.

At startup, Telepathy verifies the pinned original model files, merges Kev's adapter into the BF16 backbone, then compresses its linear/embedding weights with MXFP8 groups of 32 before creating inference caches. Temporary conversion buffers are released. Loading/conversion briefly needs the original weights in memory. The downloaded files still occupy about 1.8 GB on disk; no extra download or second model copy is required. Worker health reports the active quantization and backbone weight bytes.

The worker reuses one processed preceding-text context while pinyin and candidates change. It checks the actual encoded tokens and copies the cached attention/recurrent state before each decision. New context replaces the cache; nothing is saved to disk. In the quantization comparison, synthetic long-context ranking took about **157 ms with fresh MXFP8 context versus 110 ms when reused**, compared with 133/91 ms for BF16. MXFP8 is the default to save memory despite the latency tradeoff. All 42 Kev word choices matched BF16 in that comparison. These are worker timings, excluding native debounce and language checking, not end-to-end typing latency. The checkpoint and full prompt are unchanged; lower precision and different prefill splits can change close choices. See [the prediction experiments](../experiments/prediction/README.md) for measurements, reproduction commands and quality findings.
