# Building Telepathy

[Back to the README](../README.md)

## Requirements and build

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

The included licenses and upstream credits are collected from pinned native projects and the distributions actually collected by PyInstaller. `scripts/collect_licenses.py` can refresh them with authenticated `gh` access when dependencies change. See [CREDITS.md](../CREDITS.md), [LICENSE](../LICENSE), and `licenses/`. Thank you to the Rime, Squirrel, Wanxiang, RIME-LMDG, Kev, Qwen, MLX and Python communities.

## Further reading

- [Release verification](verification.md)
- [Prediction speed, precision and quality](../experiments/prediction/README.md)
- [Automatic language routing](../experiments/language-routing/README.md)
