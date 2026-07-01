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

## Release

Tags matching `v*` run the release workflow, which builds, signs, notarizes, publishes a GitHub Release, and bumps the `peelr` cask in `Performave/homebrew-tap`.
