# Project Telepathy

[简体中文](README.md) · **English**

<img src="assets/branding/Telepathy-128.png" alt="Telepathy icon" width="80" height="80">

**Chinese typing with a little more context.**

Telepathy is a native Chinese input method for macOS. Type pinyin as usual, and a small local model uses what you've already written to help put the right words first. Everything runs on your Mac—no account or API key required.

[Download the latest release](https://github.com/timothyzhutr/Project-Telepathy/releases/latest) · [User guide](https://github.com/timothyzhutr/Project-Telepathy/blob/main/docs/user-guide.md) · [Report an issue](https://github.com/timothyzhutr/Project-Telepathy/issues)

Telepathy is in early access. It currently supports **Apple Silicon Macs running macOS 26.2 or later**.

![Telepathy’s native candidate panel choosing 权利 after a sentence about consumer rights](docs/images/telepathy-native-demo.png)

## Features

- **Context-aware candidates.** Context prediction uses local Qwen3.5 0.8B to rank words and phrases by how naturally they follow the text before your cursor. Rime and 万象 provide the pinyin conversion and dictionaries.
- **Native typing.** Use Telepathy in your Mac apps, with normal pinyin composition, keyboard selection and a native candidate panel.
- **Chinese and English together.** Optional Auto mode uses context to keep English literal and convert Chinese pinyin. This feature is experimental.
- **Automatic punctuation forms.** In Auto mode, commas, quotes and other marks follow the language of the sentence.
- **Make it yours.** Set ranking pool size, candidates shown per page and row layout independently, alongside text size, appearance, annotations and model-assisted highlighting.
- **A starting-language hint.** With Screen Recording permission, Telepathy can read the current window when an input session activates to help choose the first word's language. Text context takes over as you type. Screenshots and word ranking share one model.
- **Local inference.** After the model download, typing assistance works offline. Your writing is not sent to a cloud service.

## Install

You do not need to install Python, Homebrew or any build tools.

1. Download and extract the macOS ZIP from [Releases](https://github.com/timothyzhutr/Project-Telepathy/releases/latest).
2. Run **Install Telepathy.command**, keeping it beside **Telepathy.app**.
3. Add **Telepathy** in **System Settings → Keyboard → Text Input → Edit → +**, then select it from the input-source menu. If it does not appear yet, log out and back in.
4. Run **Download Model.command** to install the model. Alternatively:

   ```bash
   "$HOME/Library/Input Methods/Telepathy.app/Contents/MacOS/Telepathy" --download-model
   ```

The model download needs approximately **650 MB of disk space**, in addition to the app. v0.2 uses one vision-capable model for ranking, text-language routing and screenshot hints; it does not load Kev alongside a vision model. Pinyin typing works while the model is downloading or loading. The installer backs up an existing Telepathy installation before replacing it and retains the two newest backups after a successful install.

The release is ad-hoc signed and has not been notarized by Apple. If macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** after trying to open the package. See [troubleshooting](https://github.com/timothyzhutr/Project-Telepathy/blob/main/docs/troubleshooting.md) for installation help.

## Start typing

Select Telepathy and type pinyin normally.

| Action | Key |
| --- | --- |
| Choose the highlighted candidate | Space |
| Choose a numbered candidate | Its number key |
| Browse candidates | Arrow keys |
| Use literal English manually | Caps Lock |

Selecting an English candidate with Space also adds a trailing space, without doubling the separator between consecutive English words.

Open **Telepathy → Settings…** from the input-source menu to change the candidate layout or enable **Automatic Chinese / English** and **Starting language from screen**. v0.2 uses Context prediction; the previous Kev decision head is not available on the new vision checkpoint. A teal highlight marks the selected candidate when model scoring actually ran; disable **Highlight model-assisted candidates** to use the normal highlight throughout. You can switch **Local assistance** off from the menu to stop the helper and free its memory while keeping Rime's regular candidates.

To use screenshot hints, allow Telepathy to record the screen through Settings and reopen it if macOS requests this. The settings window shows permission status. Auto mode remembers the latest definite language decision at the current typing location, so the next word uses it immediately. New text context can update it; uncertain or unavailable replies retain the decision. Moving the cursor, selecting text or changing fields resets it. Screenshots seed the initial decision when preceding text is absent; manual choices and subsequent text context take priority. Continuing to type does not capture a new screenshot for each word. Native pinyin candidates remain usable while a hint is pending.

By default, Telepathy **ranks up to 12 candidates and shows six per page**. **Candidates to rank** sets the ranking pool; **Candidates to show** sets the total visible on each page; **Candidates per row** controls layout. Both counts can be set independently from 1–12. Press **Page Down or =** for more choices and **Page Up or -** to go back. When you show more than you rank, the remaining candidates keep their original order.

Auto mode keeps confident English input literal and gives Chinese or uncertain input the usual candidate choices. Press **↓ or Tab** to bring back Chinese choices for the current word, or **Shift + a letter** to start literal English until the next space. Short words and limited context can still be ambiguous.

The model ranks candidates supplied by Rime/万象. Wanxiang can offer word and phrase completions, and the model may move a longer completion higher; it does not generate new phrases itself. Context prediction may still promote a poor match when all candidates are unsuitable. With no usable preceding context, it retains Rime's order. See the [user guide](https://github.com/timothyzhutr/Project-Telepathy/blob/main/docs/user-guide.md) for all settings, punctuation behavior and keyboard details.

## Privacy and resources

Typing context is processed locally. Telepathy does not send it to a cloud API or write it to the worker log. With screenshot hints enabled and permission granted, it captures the current application's window when an input session activates. All apps and fields share a **five-second capture cooldown**. A deferred capture runs only if the same typing location remains eligible, with no preceding text or committed first word; stale work is cancelled. Images stay in memory, are not saved or uploaded, and this is not continuous screen recording. Disable **Starting language from screen** independently at any time. Personal dictionary learning is currently disabled. The setup command downloads checksum-verified model files; inference then runs offline.

Qwen3.5 runs on the Apple GPU through MLX / MLX-VLM with **4-bit weights** occupying about **0.63 GB**. Caches, image processing and the runtime add to this: the earlier M2 Pro experiment measured about 1.3 GB resident with a higher peak during image inference. See the [single-model experiment](experiments/screen-language/SINGLE-MODEL.md). Turning assistance off stops the helper and releases its memory. Candidates appear immediately while decisions run asynchronously.

The model uses up to 100 model tokens before the cursor where you begin composing, excluding text after it. If an app does not expose preceding text, Telepathy falls back to text recently typed through the input method, which can reduce accuracy. [Resource and prediction details](https://github.com/timothyzhutr/Project-Telepathy/blob/main/experiments/prediction/README.md) include measurements and known limitations.

## Development

Want to build from source or contribute? Start with the [build guide](https://github.com/timothyzhutr/Project-Telepathy/blob/main/docs/development.md). Bugs, compatibility reports and focused pull requests are welcome. For a bug report, include your macOS version, the affected app and steps to reproduce; use a short example you're comfortable sharing.

## Credits and license

Telepathy builds on **鼠须管 / Squirrel, Rime, 万象, RIME-LMDG, Qwen, MLX, MLX-VLM** and the Python ecosystem. Earlier ranking versions used Kev, and the screenshot decision follows OpenJev's option-label readout pattern. See [CREDITS.md](CREDITS.md) for attribution and upstream links; the app also includes a native Credits and Licenses window.

Telepathy's application and integration code are licensed under [GPL-3.0](LICENSE). Dependencies and model weights retain their own licenses. Model weights are downloaded separately and are not included in the app or repository.
