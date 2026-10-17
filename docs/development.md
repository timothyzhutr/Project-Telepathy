# Building Telepathy

[Back to the English README](../README.en.md)

## Requirements and build

On Apple Silicon with macOS 26.2+, Xcode Command Line Tools and **Python 3.12**:

```bash
git clone https://github.com/timothyzhutr/Project-Telepathy.git
cd Project-Telepathy
python3.12 -m venv .venv
source .venv/bin/activate
# The lock lists the exercised runtime closure; omit upstream audio/server/training extras.
python -m pip install --no-deps -r requirements-build.txt
python scripts/prepare_assets.py
python -m PyInstaller --noconfirm --distpath .build/worker-dist --workpath .build/pyinstaller packaging/worker.spec
python scripts/build_native.py
```

`prepare_assets.py` fetches checksum-pinned upstream release inputs, compiles the active profile, and creates a reduced runtime inventory. Build caches include full upstream archives; those archives are not shipped. `dist/` contains the app and install/setup commands. The app contains only the active native interface, Rime + Lua + Octagram, deployed profile dependency closure, and local inference runtime. It omits model weights, alternate Wanxiang profiles, Sparkle updater, unused prediction plugin, research tools, training packages and the browser playground.

`packaging/inference-imports.json` records dynamic imports exercised by the active text and vision paths. To refresh it after changing inference dependencies, set up the model with `python worker/main.py --download-model`, stop the installed helper so only one model is resident, then run `python scripts/trace_inference.py "$HOME/Library/Application Support/Telepathy/models"` before freezing. The trace uses a synthetic image. The active worker loads one Qwen3.5 vision-language model; its text backbone is also the continuation scorer. Kev and the earlier screen-language benchmark are retained for research and are excluded from the executable.

The native app links ScreenCaptureKit. Screenshot hints use the input-session activation callback, require macOS Screen Recording permission, and are invalidated when the activation changes. Permission requests occur only through the user-facing settings action or explicit `--request-screen-permission` command. To inspect permission from the installed executable, run `--check-screen-permission`.

Run the checks:

```bash
python -m unittest discover -s tests
python scripts/test_native.py
python scripts/verify_package.py dist/Telepathy.app
```

The included licenses and upstream credits are collected from pinned native projects and the distributions actually collected by PyInstaller. `scripts/collect_licenses.py` can refresh them with authenticated `gh` access when dependencies change. See [CREDITS.md](../CREDITS.md), [LICENSE](../LICENSE), and `licenses/`. Thank you to the Rime, Squirrel, Wanxiang, RIME-LMDG, Kev, Qwen, MLX, MLX-VLM and Python communities.

## Further reading

- [Release verification](verification.md)
- [Prediction speed, precision and quality](../experiments/prediction/README.md)
- [Continuation ranking comparison](../experiments/prediction/continuation.md)
- [Original artwork and native demo](branding/README.md)
- [Automatic language routing](../experiments/language-routing/README.md)

For repeated local screenshot testing, sign the native app with a stable development identity rather than an ad-hoc signature:

```sh
TELEPATHY_CODESIGN_IDENTITY="Apple Development: your identity" python3 scripts/build_native.py
```

Find an available identity with `security find-identity -v -p codesigning`. You can persist the identity name or fingerprint in the ignored local file `.runtime/codesign-identity`; the environment variable takes precedence. Ad-hoc signing remains the default when neither is provided. Changing the signing identity or an ad-hoc binary hash can invalidate Screen Recording permission; a stable development identity preserves the designated requirement across subsequent rebuilds.

## Typing performance traces

`scripts/profile_typing.c` is an opt-in developer utility, excluded from the app. It reads CPU and physical-footprint counters for the installed native process and its worker, plus device-wide GPU driver utilization. It also records its own CPU use and actual sample intervals, so profiling overhead and scheduling delays remain visible. No keyboard input, screenshots or window titles are collected. Traces stop automatically at the requested duration or when a target process exits.

```sh
xcrun clang -O2 -Wall -Wextra scripts/profile_typing.c \
  -framework IOKit -framework CoreFoundation -o .build/profile-typing
ps -axo pid,comm | rg 'Input Methods/Telepathy.app'
# Substitute the two installed process IDs shown above.
.build/profile-typing NATIVE_PID WORKER_PID 180 50 .build/typing-profile.csv
```

CPU samples are 50 ms interval averages by default in this example, expressed as a percentage of one core; a multithreaded process can exceed 100%. The sampler converts Mach time ticks using the host timebase before computing CPU usage. Calibration with known 20 ms CPU bursts checks that brief activity is observable. GPU counters are queried every 100 ms and may use a different driver averaging window; held values repeat between reads. They include all applications, do not provide per-process GPU attribution, and cannot establish the absence of shorter GPU spikes. `powermetrics` offers more detailed counters with administrator access; the lightweight trace does not request it. [Apple's task-rusage implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c) describes the underlying process counters.

Stop a running trace with Ctrl+C. Read `.build/typing-profile.csv` alongside the bounded `Telepathy --screen-hint-status` history when checking capture-related spikes. Start a fresh trace after installing an update, since the native and worker PIDs change.
