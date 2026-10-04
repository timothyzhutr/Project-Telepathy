# Project Telepathy

A local, context-aware Chinese input method for macOS. 万象 and Rime generate pinyin candidates; Kev 0.8B ranks them using up to 100 model tokens of preceding text. 鼠须管 / Squirrel provides the native input interface.

This is a working prototype for experimentation. It runs in ordinary Mac applications, with a native candidate panel and normal pinyin composition. Windows support is future work.

## Install the executable

**Apple Silicon, macOS 26.2 or later.** This release bundles the executable, Python runtime and inference libraries. Homebrew, Python and an API key are not needed.

1. Download the ZIP from [Releases](https://github.com/timothyzhutr/Project-Telepathy/releases/latest) and extract it.
2. Run `Install Telepathy.command`, keeping it beside `Telepathy.app`. It installs into your own `~/Library/Input Methods` directory, and preserves an existing Telepathy app/profile in `~/Library/Application Support/Telepathy/InstallBackups`.
3. Add **Telepathy** in System Settings → Keyboard → Text Input → Edit → **+**. Select it from the input-source menu. If macOS has not discovered it yet, log out and back in.
4. Download the separately distributed Kev adapter and Qwen base model with `Download Kev Model.command`, or run:

```bash
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --download-model
```

The explicit setup command downloads only required files at pinned revisions, verifies SHA-256 checksums, and stores them in `~/Library/Application Support/Telepathy/models`. Allow approximately **1.8 GB** for weights, in addition to the app. It does not use saved Hugging Face credentials. Subsequent inference runs offline. Native pinyin typing remains available while the model is missing, loading or unavailable.

The prototype is ad-hoc signed, **not Apple-notarized**. macOS may block a downloaded app or command the first time; use System Settings → Privacy & Security → Open Anyway for the downloaded Telepathy package. A managed Mac may require administrator approval. The installer does not disable Gatekeeper.

## Use it

Type pinyin normally. Space chooses the highlighted candidate; number keys and the native candidate panel select words. Kev ranks up to 12 candidates on the current page. Short prefix candidates cannot displace a candidate that consumes the full current input. Moving through candidates manually freezes the ranking for that composition.

The input-source menu includes **Kev assistance**, which switches ranking on/off. Rime's statistical grammar continues to work when Kev assistance is off. No personal dictionary learning is enabled in this prototype. No typed text is written to the worker log or sent to a cloud API. In applications that do not expose preceding text, the IME uses limited text committed during the current session; contextual quality can be lower.

**Settings…** opens Telepathy's native settings panel above the app you're typing in. Close it with the window button or ⌘W. Preferences save automatically and apply to the candidate panel:

- Candidates per row: automatic, 1, 2, 3, 4, 6 or 12. All 12 candidates remain available; long phrases can wrap.
- Text size (12–28 pt) and appearance (follow system, light or dark).
- Inline pinyin, candidate annotations, Kev timing and the Chinese / English menu-bar status icon.
- Kev assistance and Chinese punctuation.
- Automatic Chinese / English typing (experimental, off by default).
- Automatic punctuation forms in Auto mode (on by default): Chinese or ASCII forms of the mark you press.
- Local model status, model folder access, and an explicit download / repair action. Valid pinned files are reused; missing or damaged files are fetched and verified before the worker reloads them.

Turning assistance off skips decisions; the loaded worker stays resident. Settings survive app updates. **Restore default settings** resets only Telepathy's controls, preserving model files and unrelated preferences.

Enable **Automatic Chinese / English (experimental)** in Settings while Kev assistance is on. Telepathy compares literal keyboard text with complete Chinese candidates using up to 100 tokens of preceding text. Confident English stays literal and Space adds a space; Chinese and uncertain input keep the candidate workflow. Press **↓ or Tab** to restore Chinese choices for the current word. **Shift + a letter** starts literal English until the next space. Caps Lock remains a manual English switch. Auto mode changes Shift's usual Rime language-toggle behavior.

**Automatic punctuation in Auto mode** chooses Chinese or ASCII forms from the current sentence: `这个项目叫 Telepathy，` and `I like 中文.`. It handles commas, periods, question/exclamation marks, colons, semicolons, quotes and brackets, including matching pasted opening marks. It keeps decimal/time separators, URLs, email and backtick code ASCII; pinyin apostrophes remain syllable separators during Chinese composition. An active word commits in its currently displayed language before the mark is inserted. This is a bounded native heuristic over the preceding 512 characters, with **no additional model request or wait**. It chooses the form of your key, not which punctuation mark to write. Mixed-language sentences and context unavailable from the host can still be ambiguous. Disable this setting to return to Rime's configured forms; disable **Use Chinese punctuation** to always use ASCII forms.

The language check uses the already loaded Kev backbone, with no additional model or download. It runs asynchronously before candidate ranking, during its existing debounce whenever possible. English skips pointer reranking; Chinese ranking starts at the original deadline or when a slower language check finishes. Decisions apply only to the current uncommitted snapshot. Very fast typing can outrun a decision, and short words with little context can remain ambiguous; Space uses the state visible at that instant. This is an opt-in prototype, not a calibrated intent classifier. See [the routing experiment](https://github.com/timothyzhutr/Project-Telepathy/blob/main/experiments/language-routing/README.md) for reproducible synthetic checks and limitations.

**Credits and licenses…** opens the same window on Credits. The Credits tab lists the projects used; the Licenses tab lets you browse their bundled license texts. These tabs work offline and do not launch an editor. The same texts are included under `Contents/Resources/licenses/`.

Kev's backbone runs on the Apple GPU through MLX; its small pointer head uses the CPU through PyTorch. The helper loads the model once and stays resident. Expect several GB of memory while assistance is active; actual memory and latency vary with context and hardware. Decisions are debounced and asynchronous, so native candidates appear without waiting for inference.

The worker reuses one processed preceding-text context while pinyin and candidates change. It checks the actual encoded tokens and copies the cached attention/recurrent state before each decision. New context replaces the cache; nothing is saved to disk. On the development M2 Pro, ranking the synthetic long-context cases took about **135 ms uncached versus 93 ms with cached context**. The first decision for new context still takes about 135 ms. These are worker timings, excluding the native debounce and language check, not end-to-end typing latency. The full prompt and model are unchanged. BF16 split passes can shift probabilities slightly and change nearly tied choices; the 42 ordinary cases kept their original winning choices. See [the prediction experiments](experiments/prediction/README.md) for measurements, reproduction commands and quality findings.

## Diagnose and remove

```bash
# Verify all pinned model files:
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --check-model
# Run a local ranking smoke test:
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --self-test
# Worker status (ready/loading/model_missing/error):
curl http://127.0.0.1:18765/api/health
```

The helper is loopback-only on port 18765. It accepts copied native snapshots and ranks candidates; Rime owns all composition and commits. A fresh packaged installation uses its own helper, separate from the earlier browser playground on port 8765.

To uninstall, first switch to another input source and remove Telepathy from Keyboard settings. Then run:

```bash
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --quit
pkill -x TelepathyWorker || true
rm -rf "$HOME/Library/Input Methods/Telepathy.app"
```

Your model files, profile and install backups remain for reuse. To reclaim their space, remove `~/Library/Application Support/Telepathy` and `~/Library/Telepathy` after checking the backups. Existing Squirrel or Apple input sources are separate.

## Build from source

On Apple Silicon with macOS 26.2+, Xcode Command Line Tools and **Python 3.12**:

```bash
git clone https://github.com/timothyzhutr/Project-Telepathy.git
cd Project-Telepathy
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-build.txt
python scripts/prepare_assets.py
python -m PyInstaller --noconfirm --distpath .build/worker-dist --workpath .build/pyinstaller packaging/worker.spec
python scripts/build_native.py
```

`prepare_assets.py` fetches checksum-pinned upstream release inputs, compiles the active profile, and creates a reduced runtime inventory. Build caches include full upstream archives; those archives are not shipped. `dist/` contains the app and install/setup commands. The app contains only the active native interface, Rime + Lua + Octagram, deployed profile dependency closure, and local inference runtime. It omits model weights, alternate Wanxiang profiles, Sparkle updater, unused prediction plugin, research tools, training packages and the browser playground.

`packaging/inference-imports.json` records dynamic imports exercised by the active inference path. To refresh it after changing the inference dependency versions, set up the model with `PYTHONPATH=vendor/kev python worker/main.py --download-model`, then run `python scripts/trace_inference.py "$HOME/Library/Application Support/Telepathy/models"` before freezing.

Run the checks:

```bash
python -m unittest discover -s tests
python scripts/test_native.py
python scripts/verify_package.py dist/Telepathy.app
```

The included licenses and upstream credits are collected from pinned native projects and the distributions actually collected by PyInstaller. `scripts/collect_licenses.py` can refresh them with authenticated `gh` access when dependencies change. See [CREDITS.md](CREDITS.md), [LICENSE](LICENSE), and `licenses/`. Thank you to the Rime, Squirrel, Wanxiang, RIME-LMDG, Kev, Qwen, MLX and Python communities.
