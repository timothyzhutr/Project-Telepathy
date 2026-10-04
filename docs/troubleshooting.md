# Troubleshooting and uninstalling

[Back to the English README](../README.en.md)

## Input source does not appear

Open System Settings → Keyboard → Text Input → Edit → **+**, search for Telepathy, and add it. If it is still missing after installation, log out and back in.

## macOS blocks the package

Telepathy is ad-hoc signed and has not been notarized by Apple. After attempting to open the downloaded package, use System Settings → Privacy & Security → Open Anyway. A managed Mac may require administrator approval.

## Kev is not ready

Open Telepathy → Settings to check model status. Use **Download / Repair** if model files are missing or damaged. Pinyin candidates remain available while the model is loading or unavailable.

## Local diagnostics

```bash
# Verify all pinned model files:
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --check-model
# Run a local ranking smoke test:
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --self-test
# Worker status (ready/loading/model_missing/error):
curl http://127.0.0.1:18765/api/health
```

The helper is loopback-only on port 18765. It accepts copied native snapshots and ranks candidates; Rime owns all composition and commits. 

## Profile recovery

Telepathy repairs an incomplete compiled Rime profile using a staged copy. When it replaces an existing incomplete `build` directory, the displaced files remain in `~/Library/Telepathy/Rime/.build-incomplete-…` for manual recovery. A complete profile is left intact.

Successful installs keep the two newest completed app/profile backups. Interrupted or failed installs marked as in progress are excluded from automatic pruning.

## Uninstall

First switch to another input source and remove Telepathy from Keyboard settings. Then run:

```bash
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --quit
pkill -x TelepathyWorker || true
rm -rf "$HOME/Library/Input Methods/Telepathy.app"
```

Your model files, profile and install backups remain for reuse. To reclaim their space, remove `~/Library/Application Support/Telepathy` and `~/Library/Telepathy` after checking the backups. Existing Squirrel or Apple input sources are separate.
