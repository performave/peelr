# Peelr

An intelligent background remover for macOS, built for the lecture-slide → GoodNotes
workflow — but it handles real photos too.

## Why

macOS's built-in **Remove Background** uses Vision subject-lifting, which looks for a
distinct foreground *object*. Lecture slides have no such subject (just text/diagrams on a
flat color), so it fails on exactly the images you want to clean up. Peelr adds a dedicated
**color-key** engine for slides — and, crucially, it removes the background *everywhere*, so
the enclosed counters of letters (the holes in **O**, **a**, **e**, **P**) become transparent
instead of staying filled.

For photos, Peelr can bundle **BiRefNet** (a state-of-the-art Core ML matting model) for
edge/hair quality beyond the system tool, with Apple's Vision as an automatic fallback.

## Features

- **Clipboard workflow**: copy a slide → press **⌥⌘B** → paste a transparent PNG into GoodNotes.
- **Three triggers**: global hotkey (no Accessibility permission needed), menu bar item, and Apple Shortcuts.
- **Auto mode**: detects slide vs. photo from the image; override in the window.
- **Color-key engine** (slides): perceptual CIELAB keying with feathered edges; optional
  "protect interior content" (flood-fill) toggle for photos with uniform backgrounds.
- **Photo engine**: bundled BiRefNet Core ML, falling back to Vision subject-lift if the model is absent.
- **Editor window**: drag-drop, before/after preview over a transparency checkerboard, tolerance/feather sliders, copy/save.

## Build & run

Requires Xcode 16+ and [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Peelr.xcodeproj -scheme Peelr -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Peelr-*/Build/Products/Debug/Peelr.app
```

For Shortcuts and the global hotkey to behave well, move the built `Peelr.app` to
`/Applications` and launch it once so Launch Services registers its App Intents.

## Apple Shortcuts

After launching once, the **Remove Background** and **Remove Background from Clipboard**
actions appear in the Shortcuts app. To get a system hotkey via Shortcuts, build a shortcut
(e.g. Get Clipboard → Remove Background → Copy to Clipboard) and assign it a key in the
Shortcuts app — complementary to Peelr's built-in ⌥⌘B.

## The BiRefNet model (optional)

Peelr runs without the model (it falls back to Vision). To enable the high-quality photo
engine, produce `Resources/BiRefNet.mlpackage`:

Dependencies are declared in `pyproject.toml` and run with [uv](https://docs.astral.sh/uv/):

```sh
uv run scripts/convert_birefnet.py --output Resources/BiRefNet.mlpackage
xcodegen generate && xcodebuild ... build   # rebuild to bundle it
```

Or drop a precompiled `BiRefNet.mlmodelc` / `BiRefNet.mlpackage` into `Resources/`.
BiRefNet is MIT-licensed.

## Notes

- The app is non-sandboxed by default for the simplest clipboard + global-hotkey behavior.
- The generated `Peelr.xcodeproj` is not committed; `project.yml` is the source of truth.
