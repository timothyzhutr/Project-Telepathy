# Credits and licenses

Project Telepathy builds on the work of these open-source communities. Thank you to their authors and contributors.

| Component | What Telepathy uses | Source and license |
| --- | --- | --- |
| 鼠须管 / Squirrel | macOS InputMethodKit integration, composition, keyboard handling, candidate panel and themes; modified Swift sources | [rime/squirrel](https://github.com/rime/squirrel/tree/0cd71a6130a5866b0ae6ba0494929ebdc8211194), GPL-3.0 |
| librime 1.17.0 | Pinyin conversion, segmentation, candidate lists and commits | [rime/librime](https://github.com/rime/librime/tree/1.17.0), BSD-3-Clause |
| librime-lua | Wanxiang Lua processors, translators and filters | [hchunhui/librime-lua](https://github.com/hchunhui/librime-lua/tree/ec52e48), BSD-3-Clause; embedded [Lua](https://www.lua.org/), MIT |
| librime-octagram | Context scoring using the Wanxiang grammar | [lotem/librime-octagram](https://github.com/lotem/librime-octagram/tree/dfcc151), BSD-3-Clause |
| 万象 / rime-wanxiang v18.0.15 | Full-pinyin schema, required compiled Chinese/English/mixed/reverse dictionaries, Lua utilities and conversion data | [amzxyz/rime-wanxiang](https://github.com/amzxyz/rime-wanxiang/tree/v18.0.15), CC-BY-4.0; see its upstream acknowledgments for dictionary/data contributors |
| RIME-LMDG | `wanxiang-lts-zh-hans.gram`, the active statistical grammar | [amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG), CC-BY-4.0 |
| Kev 0.8B | Encoder, adapter and pointer-head candidate decisions; loaded backbone reused for contextual language routing; inference source subset | [jaredpalmer/kev](https://github.com/jaredpalmer/kev/tree/84847f0a883d900f7de5b7a57eaa341ca7f9a6b4), Apache-2.0; [model](https://huggingface.co/jaredpalmer/kev-0.8b) downloaded separately |
| Qwen3.5 0.8B Base | Kev's underlying text model and tokenizer, downloaded separately | [Qwen/Qwen3.5-0.8B-Base](https://huggingface.co/Qwen/Qwen3.5-0.8B-Base), Apache-2.0 |
| MLX and MLX-LM | Apple Silicon Metal inference | [ml-explore/mlx](https://github.com/ml-explore/mlx), [ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm), MIT |
| PyTorch | Kev pointer head and checkpoint loading | [pytorch/pytorch](https://github.com/pytorch/pytorch), BSD-3-Clause and bundled third-party notices |
| Transformers, Tokenizers, Hugging Face Hub, Safetensors | Tokenizer, pinned model setup and weight loading | [Hugging Face](https://github.com/huggingface), Apache-2.0 |
| CPython, PyInstaller | Bundled Python runtime and executable bootloader | [Python](https://www.python.org/), PSF; [PyInstaller](https://pyinstaller.org/), GPL-2.0-or-later with bootloader exception |

librime's embedded libraries include OpenCC (Apache-2.0), Boost (BSL-1.0), marisa-trie (BSD-2-Clause/LGPL notices as supplied upstream), LevelDB (BSD-3-Clause), glog (BSD-3-Clause), yaml-cpp (MIT), Darts-clone (BSD-2-Clause), and utf8cpp (BSL-1.0). Their notices are preserved under `licenses/`. The vendored Rime key-symbol header preserves the X11 notice.

`licenses/python-dependencies.json` records the bundled Python runtime distributions and their versions. `licenses/python/` preserves their license texts, including transitive dependencies and third-party notices. The app includes this same directory under `Contents/Resources/licenses/`.

## Changes to upstream work

Telepathy's Squirrel fork adds asynchronous Kev ranking, experimental context-based Chinese/English routing, native contextual punctuation forms, input-coverage checks, stale-response rejection, display-to-Rime candidate mapping, preceding-text extraction, isolated profile storage, bundled-worker startup, model setup commands, persistent native settings, configurable candidate rows and text size, a native credits/licenses window and Telepathy branding. Updater/deployment/sync UI that is unused in the packaged prototype is omitted. Original source authorship headers are retained.

Wanxiang's active full-pinyin profile is compiled with a 12-candidate page, static context scoring enabled, personal dictionary learning disabled, and personal-context/manual-order/statistics modules removed. Only the reference closure of its remaining schema is packaged. Raw dictionaries already represented by compiled binaries, alternate pinyin profiles, unused Lua modules and prediction plugins are omitted. The small typo-comment dictionary is retained because its Lua filter reads it directly.

Kev's vendored inference files are unmodified at the pinned revision. Telepathy's loader supplies verified local base-model paths instead of resolving a Hugging Face identifier during inference. It uses the official encoder, LoRA merge, head weights, calibration and answer conversion.

Telepathy's language router is an additional implementation that compares natural continuation likelihoods through that same loaded backbone. Its normalized alternative scores are separate from Kev's calibrated pointer-head outputs and are not calibrated probabilities of human language intent.

Telepathy's punctuation policy is original native code that selects Chinese or ASCII forms from bounded preceding text. It uses no model inference or additional upstream component.

Project Telepathy's native application and original integration code are distributed under GPL-3.0. Independently licensed dependencies and data retain their respective licenses. Model weights are never included in the source repository or app release. Corresponding application source, build scripts, upstream revisions, notices and dependency locks are available in [Project Telepathy](https://github.com/timothyzhutr/Project-Telepathy). No affiliation or endorsement by upstream authors is implied.
