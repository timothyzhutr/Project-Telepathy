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

Kev's backbone runs on the Apple GPU through MLX; its small pointer head uses the CPU through PyTorch. The helper loads the model once and stays resident. Expect several GB of memory while assistance is active; actual memory and latency vary with context and hardware. Decisions are debounced and asynchronous, so native candidates appear without waiting for inference. The development M2 Pro achieved roughly 100 ms for a short two-candidate decision and 117 ms for a 12-candidate native snapshot after warm-up; this is a smoke-test result, not a typing benchmark.

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
xcrun swiftc native/Sources/RankingState.swift native/Tests/RankingStateTests.swift -o .build/ranking-tests
.build/ranking-tests
python scripts/verify_package.py dist/Telepathy.app
```

The included licenses and upstream credits are collected from pinned native projects and the distributions actually collected by PyInstaller. `scripts/collect_licenses.py` can refresh them with authenticated `gh` access when dependencies change. See [CREDITS.md](CREDITS.md), [LICENSE](LICENSE), and `licenses/`. Thank you to the Rime, Squirrel, Wanxiang, RIME-LMDG, Kev, Qwen, MLX and Python communities.
