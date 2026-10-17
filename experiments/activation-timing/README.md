# IME activation lead time

Measured on an Apple M2 Pro, 16 GiB, macOS 27.0.1, 2026-10-17.

**Telepathy's existing `activateServer` callback can arrive before typing with a useful head start.** All 11 first-key samples in this short session followed activation. This supports using the callback to start a speculative screenshot-language hint.

| App | First-key samples | Activation-to-key range | Median |
|---|---:|---:|---:|
| Codex | 4 | 315–2,242 ms | 505 ms |
| TextEdit | 1 | 915 ms | 915 ms |
| Firefox | 6 | 116–591 ms | 406 ms |

The Firefox fixture had two text areas and a link opening a second test tab. The user interacted with both fields and the second tab. The native trace does not identify individual fields or tabs, so it cannot establish a one-to-one mapping between each physical focus change and an activation callback. The same Firefox controller object was reused across multiple activations.

Seven of eleven samples had at least the roughly 430 ms needed by the previous **warm** image-inference benchmark. This is only a comparison of measured intervals. Screen capture, settling/debounce, IPC and worker scheduling would consume additional time; a cold model load would take much longer. Some interactions would therefore hide only part of the latency. These were prompted tests with brief pauses, not a representative typing-delay distribution. Notes, Safari and Chrome were not measured.

## Method

`build_probe.py` compiles the current production controller with three timestamp hooks inserted into a temporary source copy: entry to `activateServer`, entry to `deactivateServer`, and the first key-down handled after activation. Production source files are not edited. The diagnostic build disables ranking and helper startup without changing user preferences.

The first-key event's `NSEvent.timestamp` is compared with activation's `ProcessInfo.systemUptime`; the received-key timestamp is also retained to expose delivery delay. The trace contains only event types, timing, a generated controller identifier, application bundle ID and process ID. It does not record key codes, characters, text, window titles or screenshots. Logging stops when the experiment's `enabled` sentinel is removed.

Initial attempts to send keys into background app windows through automation produced no IME callbacks and were excluded. The reported first-key samples came from subsequent human interaction. There were 30 recorded activations and 11 first-key samples; many activations had no typing. This is a reason to coalesce brief activation bursts rather than run expensive inference unconditionally for each notification.

[`results.json`](results.json) contains the measurements and sanitized event records. The original local trace, build logs, pre-probe executable/signature backup and restoration receipt are under `.runtime/activation-timing/`, outside Git. The scratch TextEdit document was saved in that same isolated directory, and the two browser fixture tabs and local fixture server were closed.

## Restoration and checks

`probe_session.py` swaps only the native executable and backs up its original signature. Its `finally` block restores both, including on a stop signal or after a 20-minute deadline. It returns the selected input source to its original value. The installed app's resources, model files and preferences are not replaced.

The installed executable was restored byte-for-byte to SHA-256 `bce7aa933d5f3e2f8531f2113b3e47f3df23d1e0c3b97d6a3c107266978ac1a7`; its original signature passed deep/strict verification. The original input source was ABC–Extended. No diagnostic logging or screenshot feature remains enabled in the packaged app.

`TraceStateTests.swift` first failed on a missing activation record, then passed after implementing the recorder. It checks first-key-only recording, deactivation invalidation, preservation of negative lead times and the absence of text/key-code fields. The instrumented native controller also compiled successfully.

## Reproduce

Use an existing installed and signed Telepathy app, the repository's pinned native build assets and an Apple Silicon macOS SDK. Run from the repository root, with the native app stopped. Inspect and archive a previous `.runtime/activation-timing/original` backup before starting another session; the runner refuses to overwrite it.

```bash
mkdir -p .runtime/activation-timing
xcrun swiftc experiments/activation-timing/TraceState.swift \
  experiments/activation-timing/TraceStateTests.swift \
  -o .runtime/activation-timing/state-tests
.runtime/activation-timing/state-tests
python3 experiments/activation-timing/build_probe.py
xcrun swiftc experiments/activation-timing/input_source.swift \
  -o .runtime/activation-timing/input-source
```

Ensure no old `stop` sentinel remains before running `python3 experiments/activation-timing/probe_session.py`. Select Telepathy in each test app, change typing destination, and type a few harmless characters. The fixture can be served using `python3 -m http.server 19878 --bind 127.0.0.1 --directory experiments/activation-timing`. End the probe with `touch .runtime/activation-timing/stop`, wait for its restoration message and verify the installed signature before resuming normal use.

For a first implementation, use activation to start the existing single resident vision-capable model's screenshot decision, associate it with an activation revision, and discard obsolete results. Keep native typing responsive when the hint is not ready. Subsequent text context and manual language selection should take precedence. This experiment validates the timing opportunity; it does not implement or benchmark that complete capture/inference pipeline.
