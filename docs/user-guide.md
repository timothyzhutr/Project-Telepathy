# Using Telepathy

[Back to the English README](../README.en.md)

## Installation

**Apple Silicon, macOS 26.2 or later.** This release bundles the executable, Python runtime and inference libraries. Homebrew, Python and an API key are not needed.

1. Download the ZIP from [Releases](https://github.com/timothyzhutr/Project-Telepathy/releases/latest) and extract it.
2. Run `Install Telepathy.command`, keeping it beside `Telepathy.app`. It installs into your own `~/Library/Input Methods` directory, and preserves an existing Telepathy app/profile in `~/Library/Application Support/Telepathy/InstallBackups`. Successful installs retain the two newest completed backups; failed installs preserve previous backups.
3. Add **Telepathy** in System Settings → Keyboard → Text Input → Edit → **+**. Select it from the input-source menu. If macOS has not discovered it yet, log out and back in.
4. Download the separately distributed Qwen3.5 vision model with `Download Model.command`, or run:

```bash
"$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --download-model
```

The explicit setup command downloads only required files at pinned revisions, verifies SHA-256 checksums, and stores them in `~/Library/Application Support/Telepathy/models/vision`. Allow approximately **650 MB** for model files, in addition to the app. It does not use saved Hugging Face credentials. Subsequent inference runs offline. Native pinyin typing remains available while the model is missing, loading or unavailable. An upgrade from v0.1 needs this new model download; the old Kev files are not loaded alongside it.

Telepathy is ad-hoc signed, **not Apple-notarized**. macOS may block a downloaded app or command the first time; use System Settings → Privacy & Security → Open Anyway for the downloaded Telepathy package. A managed Mac may require administrator approval. The installer does not disable Gatekeeper.

## Typing and settings

Type pinyin normally. Space chooses the highlighted candidate and adds a trailing space when that candidate is English. Number keys and the native candidate panel select visible words without adding that separator. By default, the model ranks up to 12 candidates from Rime's first page and shows six at a time. Candidates consuming less input than Rime's first candidate stay behind that group within the ranking pool. Manual navigation freezes the current list until the input changes.

Use **Page Down or =** to reveal more choices and **Page Up or -** to go back. Paging reveals the remainder of the current Rime page before moving to another native page; later native pages retain Rime's order. Number labels start again on each displayed page, and Up/Down stay within its visible choices. Left/Right also browse the displayed order in a horizontal layout; in a vertical layout they retain their pinyin-caret behavior. A number key without a visible candidate is ignored.

The input-source menu includes **Local assistance**, which switches model assistance on/off. Rime's statistical grammar continues to work with it off. No personal dictionary learning is enabled. No typed text is written to the worker log or sent to a cloud API. In applications that do not expose preceding text, the IME uses limited text committed during the current session; contextual quality can be lower.

**Settings…** opens Telepathy's native settings panel above the app you're typing in. Close it with the window button or ⌘W. Preferences save automatically and apply to the candidate panel:

- Candidates to show: **6 by default**, adjustable from 1–12. This is the total visible on each displayed page, including when model assistance is off. Paging keeps the other candidates accessible.
- Candidates to rank: **12 by default**, adjustable from 1–12. The worker receives up to this many candidates from Rime's first page; candidates outside that pool stay in their original order after it. Showing more than are ranked is allowed. A smaller pool can reduce scoring work but excludes potential matches; 1 leaves no choice to rerank. Chinese/English routing still considers the full native candidate pool.
- Candidates per row: automatic, 1, 2, 3, 4, 6 or 12. This controls layout independently of the display total; long phrases can wrap.
- Text size (12–28 pt) and appearance (follow system, light or dark).
- Inline pinyin, candidate annotations, model-assisted highlighting and the Chinese / English menu-bar status icon.
- Local assistance and Chinese punctuation.
- Context prediction ranks natural continuations of your preceding text. With no usable context it retains Rime's order. It has no explicit no-fit option, and scores are not probabilities of your intent. v0.2 replaces the earlier Kev model and pointer-head alternative with the tested vision checkpoint; it uses continuation scoring for all word-ranking requests.
- Automatic Chinese / English typing (experimental, off by default).
- Starting language from screen (experimental, on by default when Auto mode is enabled), screen-recording permission status and an explicit permission action.
- Automatic punctuation forms in Auto mode (on by default): Chinese or ASCII forms of the mark you press.
- Local model status, model folder access, and an explicit download / repair action. Valid pinned files are reused; missing or damaged files are fetched and verified before the worker reloads them.

Turning assistance off stops the model helper, releasing its model, caches and inference runtime. Turning it on starts the helper again; ordinary Rime typing stays available while the model reloads. Model files remain on disk. Settings survive app updates. **Restore default settings** resets only Telepathy's controls, preserving model files and unrelated preferences.

**Highlight model-assisted candidates** uses a teal highlight on the selected candidate when the model actually evaluated it, including when the evaluated order stays unchanged. Candidates outside the scoring pool, shorter fragments excluded from scoring, missing-context fallbacks and single-choice shortcuts retain the normal highlight. The accent indicates model involvement, not confidence or correctness. Timings remain available in worker diagnostics rather than the typing panel.

Ranking uses preceding text at the insertion point where the composition began, capped at 100 model tokens. Text after that point is not included. Within a composition, confirmed Chinese segments become part of the prefix. If the host does not expose surrounding text, the input method falls back to its recent committed text; that fallback cannot reliably follow edits elsewhere in the document.

The model only ranks candidates supplied by Rime/万象. Wanxiang's dictionary completion is enabled, so a candidate can extend a partial spelling into a longer word or phrase; scoring can promote that completion. It does not generate new text, and a suggested completion is committed through the normal selection/commit actions.

Enable **Automatic Chinese / English (experimental)** in Settings while Local assistance is on. Telepathy compares literal keyboard text with complete Chinese candidates using up to 100 tokens of preceding text. English stays literal and Space adds a space. The latest definite text or screen decision becomes the default for subsequent words at that typing location, including while the next request is pending or unavailable. A fresh contextual decision can change it. **↓ or Tab** restores Chinese choices and remembers Chinese as the default; a later contextual decision may update subsequent words. **Shift + a letter** starts literal English until the next space. Caps Lock remains a manual English switch. Auto mode changes Shift's usual Rime language-toggle behavior.

The default resets when the host reports a different client, cursor position, selected range or field location. Telepathy accounts for its own commits and passed-through typing, so ordinary word boundaries do not count as cursor moves. Selection is checked on activation, input events and before applying model replies, without continuous polling. Hosts that omit selection or caret data can limit detection, and a same-field click without an activation callback is detected at the next input event. Settings changes also clear the retained decision. A new location starts with native Chinese candidates while its first decision is pending.

A capitalized word such as `Python` stays in one marked composition, with Chinese candidates hidden. Space commits the complete word and one space; Backspace edits it, Escape cancels it, and punctuation/shortcuts commit it before their normal action. Letter case and apostrophes are preserved. If the host explicitly commits a segment during a same-location lifecycle callback, the remaining letters retain the temporary English override. This preserves an established Chinese default for subsequent words: `Python` followed by `nihao` can produce `Python 你好`. A fresh contextual decision can still change the default. When no definite default exists yet, the capital seeds English; an actual cursor or field change clears the temporary override.

**Starting language from screen** uses a screenshot of the current application's window at a new typing location, with a first-key fallback if activation was missed. The focused input location is marked for the model where the host supplies its caret position. Rapid activation changes are coalesced and stale replies are discarded. A result is accepted only while there is no usable preceding text and the first word remains uncommitted. Once accepted, its language can seed subsequent words until text or a manual choice replaces it, or the cursor changes. Continuing in the same location does not trigger another screenshot on each word or duplicate activation. A busy or unavailable model leaves native typing usable; the app never waits for the screen hint before handling a key.

Captures share a **five-second minimum interval** across every input controller, app and field. Failed capture attempts also consume the interval; an unavailable caret does not. An eligible new focus during the cooldown is deferred, and its current permission, cursor and text context are checked again before capture. Committing the first word, changing focus or disabling the feature cancels the deferred work. Idle time does not build up an allowance for a burst of captures. Text routing and ordinary candidate ranking remain asynchronous and are not delayed by this screenshot cooldown.

Allow Telepathy in **System Settings → Privacy & Security → Screen & System Audio Recording** using the permission action in Settings. Follow macOS's reopen request if shown. The settings panel reports permission status. Disabling screen hints or Auto mode prevents new captures. Secure-input sessions are excluded. Images remain in memory, are processed locally through the loopback helper, and are never saved, logged or uploaded. The permission covers screen capture, but this feature captures individual active windows rather than continuously recording the display. Mixed-language pages and ambiguous first words can still produce an incorrect hint.

Language checking and ranking start after an 85 ms pause in typing. New keystrokes cancel pending work; manual candidate navigation freezes the current choice. Symbol/reverse-lookup input and later native candidate pages use Rime directly.

**Automatic punctuation in Auto mode** chooses Chinese or ASCII forms from the current sentence: `这个项目叫 Telepathy，` and `I like 中文.`. It handles commas, periods, question/exclamation marks, colons, semicolons, quotes and brackets, including matching pasted opening marks. It keeps decimal/time separators, URLs, email and backtick code ASCII; pinyin apostrophes remain syllable separators during Chinese composition. An active word commits in its currently displayed language before the mark is inserted. This is a bounded native heuristic over the preceding 512 characters, with **no additional model request or wait**. It chooses the form of your key, not which punctuation mark to write. Mixed-language sentences and context unavailable from the host can still be ambiguous. Disable this setting to return to Rime's configured forms; disable **Use Chinese punctuation** to always use ASCII forms.

Language checks and screen hints use the same loaded Qwen model as word ranking. After the typing debounce, text routing runs asynchronously before candidate ranking. English skips candidate reranking; Chinese and uncertain judgments proceed to ranking. Decisions apply only to the current uncommitted snapshot. Very fast typing can outrun a decision; Space uses the state visible at that instant. Screen inference can occupy the single worker for several hundred milliseconds, so activation starts it early where possible. Auto scores are not calibrated probabilities of intent. The [single-model experiment](../experiments/screen-language/SINGLE-MODEL.md) records synthetic accuracy, latency and limitations.

**Credits and licenses…** opens the same window on Credits. The Credits tab lists the projects used; the Licenses tab lets you browse their bundled license texts. These tabs work offline. The same texts are included under `Contents/Resources/licenses/`.

If the input-source menu shows a solid square after updating Telepathy, macOS may still have the old icon cached. Open **Activity Monitor**, search for **TextInputMenuAgent**, select that exact process, and choose **Stop → Quit**. macOS relaunches the menu helper; reopen the input-source menu to check the logo. This resolved the stale icon after the v0.2.2 update without signing out.

The single Qwen3.5-0.8B vision-language model runs on the Apple GPU through MLX / MLX-VLM with **4-bit affine weights, group size 64**. Its weight arrays occupy about **625 MB**. Activations, image tensors, inference caches and runtime memory are additional: the earlier M2 Pro experiment measured about **1.3 GB resident** and an observed **2.3 GB peak**. Those are research-process measurements, not a guarantee for every app session. The helper stays resident while assistance is enabled. Native candidates remain usable during asynchronous decisions.

At startup, Telepathy verifies the pinned checkpoint/tokenizer/processor files and loads the already quantized model. Text scoring and image decisions use views of those same weights. Image requests get fresh multimodal cache state so they do not alter the retained text-prefix cache. Worker health identifies the model, vision support, quantization and weight bytes.

The worker reuses one processed preceding-text context while pinyin and candidates change. It checks the actual encoded tokens and copies cached attention/recurrent state before scoring. New context replaces the cache; nothing is saved to disk. The vision model's earlier synthetic comparison measured roughly **50 ms with fresh context versus 32 ms when reused**, and **425–444 ms** for warm image requests. These exclude native capture, debounce, IPC and scheduling and are not end-to-end typing latency. See the [single-model experiment](../experiments/screen-language/SINGLE-MODEL.md) for measurements and limitations.
