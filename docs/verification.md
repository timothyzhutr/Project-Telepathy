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
- Native settings regressions exercise real AppKit control actions, persisted preferences, the actual TextKit candidate panel with 12 candidates arranged as four rows of three, saved font size, direct-tab model health, and scoped reset. Visual QA checks the preview, scrolling and controls in the native window. Health's HTTP boundary is stubbed in the UI regression; packaged worker health is checked separately.
- Model repair rejects a corrupt file even when its size and modification timestamp are unchanged, forces a fresh pinned download, and reuses other valid files without network access.
- Utility-panel presentation is checked against a separate covering application using real WindowServer ordering, with the activation request boundary forced to decline. The covering app raises its normal window again after Telepathy opens, reproducing a menu dismissal covering the settings window. The previous normal-window implementation fails this check; the floating, nonactivating panel stays above the host. The fixture exits if its parent test dies. This regression does not verify another app's full-screen Space.

The ranking smoke examples are synthetic and are not a quality benchmark. Packaged physical-keyboard activation on a fresh account remains a manual installation check. macOS input-source registration can require adding Telepathy in Keyboard settings and logging out/back in.
