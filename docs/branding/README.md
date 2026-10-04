# Telepathy artwork and native demo

The **Context link** mark is original Telepathy artwork: two text brackets around two connected points. The brackets represent written context; the rising link represents the word that fits it. A two-unit stroke keeps the shape legible at 16–22 pixels. The macOS app tile uses the same mark on a green gradient, with transparent margins and rounded corners.

Copyright 2026 Project Telepathy contributors. The original artwork and rendering scripts are licensed under **GPL-3.0-only**, matching this repository. No Rime or Squirrel logo artwork is incorporated.

## Build the artwork

```sh
python3 scripts/build_branding.py
python3 scripts/build_branding.py --preview
```

The generator uses Python's standard library, the macOS Swift compiler, AppKit/CoreGraphics, and `iconutil`. There are no extra graphics dependencies. It reads the canonical paths and circles from `assets/branding/Telepathy.svg`, and tile geometry and colors from `Telepathy-app.svg`.

- `Telepathy.icns`: 16, 32, 128, 256, and 512 point images, each with a 2× representation.
- `Telepathy.pdf`: an 18×18 point, black, transparent vector template for the input-source/menu icon.
- `Telepathy-128.png`: the app tile for the README.
- `brand-preview.png`: optional documentation preview of the mark at 16, 18, and 22 points in light and dark surroundings. This preview is not an app resource.

Only the app icon and template PDF need to be copied into the application bundle. `logo-concepts.svg` remains an archival design study.

## Render the native demo

```sh
python3 scripts/render_demo.py
python3 scripts/render_demo.py --replay
```

The live command reads the bundled Wanxiang schema through librime in a fresh temporary profile and makes one request to the existing loopback worker. It renders the production `SquirrelPanel`, including its actual TextKit layout, native highlighting, fonts, and twelve-candidate grid. The document and captions are an isolated AppKit fixture. Preferences use the fixture's own bundle identifier, and no user clipboard or document is read.

The synthetic preceding text is `作为消费者，我们有依法要求商家提供合格产品的`, followed by `quanli`. The original native candidate order starts with `全力`; the captured local Kev decision puts `权利` first, followed by `权力` and `全力`. `native-demo.json` preserves the synthetic request, native candidates and candidate lengths, and the actual worker response. The screenshot uses four candidates per row at 22 points, with optional candidate annotations and timing turned off.

`--replay` validates the bundled candidates and context against that saved snapshot, then renders the same production panel without calling the model. The output is `docs/images/telepathy-native-demo.png`, at 2240×1148 pixels. It is an AppKit view capture of the documented fixture, not an OS-wide screenshot.
