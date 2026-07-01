# AGENTS.md

## Project

Peelr is a macOS Swift/Xcode app for removing image backgrounds, optimized for slide-to-notes workflows.

## Commands

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project Peelr.xcodeproj -scheme Peelr -configuration Debug -destination 'platform=macOS'
xcodebuild -project Peelr.xcodeproj -scheme Peelr -configuration Debug build
```

## Conventions

- Use Conventional Commits.
- `project.yml` is the XcodeGen source of truth.
- Keep engine changes covered by XCTest regression tests where practical.
- Do not commit generated build products, DerivedData, or Core ML model artifacts.

## Core ML model (BiRefNet)

- The photo engine (`BiRefNetMatter`) uses a ~233 MB Core ML model. It is **not bundled** — that
  would bloat every app update (Homebrew casks redownload in full). `ModelStore` downloads it on
  demand (first photo-mode use), compiles it, and caches it in
  `~/Library/Application Support/Peelr/Models/BiRefNet-<revision>.mlmodelc`, reused across launches
  and app updates. Until it's ready, `BackgroundRemover` falls back to `VisionSubjectMatter`.
- Source: `VincentGOURBIN/RMBG-2-CoreML` (int8), pinned by revision in `ModelStore`. It's
  **CC BY-NC 4.0 (non-commercial)** — fine only while Peelr is not sold. MultiArray `input` (caller
  applies ImageNet mean/std), logits output `output_3` (`BiRefNetMatter` applies sigmoid).
- Alternative: `uv run scripts/convert_birefnet.py` converts the MIT BiRefNet locally.
- Compute units: use `.cpuAndGPU`, **not** `.all`. Compiling this int8 model for the Neural Engine
  stalls for minutes; CPU+GPU loads in seconds and runs a warm matte in ~0.8s.

## Release

Tags matching `v*` run the release workflow, which builds, signs, notarizes, publishes a GitHub Release, and bumps the `peelr` cask in `Performave/homebrew-tap`.
