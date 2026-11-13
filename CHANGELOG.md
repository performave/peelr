# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0]

The first release.

### Added

- Copy an image, press ⌥⌘B, and paste a transparent PNG into any app. The hotkey can be changed or turned off in Settings, and needs no Accessibility permission.
- The same removal from the menu bar's scissors icon, from **Remove Background (Peelr)** under Quick Actions / Services when you right-click an image in Finder, and from the **Remove Background** actions in the Shortcuts app.
- Auto mode tells a slide from a photo, and you can override it in the editor.
- A slide engine for flat backgrounds that also clears enclosed letter counters, the holes in O, a, e and P, with a tolerance control and an optional **Protect interior content** setting.
- A photo engine based on the RMBG-2 Core ML model. It downloads once, about 233 MB, the first time you remove a photo's background, and is kept across updates. Until it is ready, Apple's Vision subject lifting is used instead.
- An editor window with drag and drop, side-by-side and hover-reveal comparison with shared zoom and pan, processing progress, and copy or save as PNG.

### Install

```sh
brew install --cask performave/tap/peelr
```

This release is ad-hoc signed and not notarized. The Homebrew cask removes the quarantine that would otherwise make macOS refuse to open it. If you download the zip by hand instead, run `xattr -dr com.apple.quarantine Peelr.app` before opening it.
