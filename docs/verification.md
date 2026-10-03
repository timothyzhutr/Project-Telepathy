# Prototype release verification

The native development input method was confirmed to accept physical keyboard input before packaging. The packaged v0.1.0 app and bundled worker were then installed from the release archive; the user confirmed Chinese input in Codex. The native information window added in v0.1.1 is checked separately from ranking and typing.

Package checks cover:

- Pinned and checksum-verified upstream assets and model-file manifest.
- Pruned Wanxiang profile: expected candidates for `nihao`, `butaixing`, `quanli`, `moxing`, and `zhongwen` in an isolated Rime session.
- A complete runtime inventory: no personal dictionaries, QA logs, alternate profiles, unused prediction plugin, updater framework, or neural weights.
- Apple Silicon Mach-O linkage, bundled binary minimum OS versions, strict/deep signature verification, and InputMethodKit controller class lookup.
- Relocated app path containing spaces, with no Python/Homebrew on PATH. Native CLI forwarding reaches the bundled Kev worker.
- Real offline inference with the pinned existing weights: consumer-rights context chooses `权利`, including a copied 12-candidate native snapshot, while preserving shorter-span candidates after the fully covered group.
- Missing-model native-order fallback and foreign HTTP origin rejection.
- Candidate coverage, stale-response rejection, manual selection freeze, partial composition mapping, model corruption detection, explicit downloader file/revision/credential controls, and installer rollback on a failed profile backup.
- The actual credits menu action opens a retained native window with readable credits and selectable license texts, without launching an external editor. Native regressions cover initial tab selection, bytecode/cache exclusion, unreadable-file handling, Copy/Select All/Close key equivalents, and closing/reopening one window. Copy's final action is intercepted in the test to preserve the user's clipboard.
- Lua's MIT notice is preserved as plain text with its source URL, without HTML markup or external resource loading. Package checks exclude Python cache files from the license directory.

The ranking smoke examples are synthetic and are not a quality benchmark. Packaged physical-keyboard activation on a fresh account remains a manual installation check. macOS input-source registration can require adding Telepathy in Keyboard settings and logging out/back in.
