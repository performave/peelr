# Development

Peelr is a macOS Swift app generated with XcodeGen. `project.yml` is the source of truth for the Xcode project.

## Requirements

- macOS 14 or newer
- Xcode 16 or newer
- XcodeGen

```sh
brew install xcodegen
```

## Generate the Xcode project

```sh
xcodegen generate
open Peelr.xcodeproj
```

Do not edit the generated project by hand. Change `project.yml`, then regenerate.

## Build

```sh
xcodebuild -project Peelr.xcodeproj -scheme Peelr -configuration Debug build
```

To launch the debug app after building:

```sh
open ~/Library/Developer/Xcode/DerivedData/Peelr-*/Build/Products/Debug/Peelr.app
```

For Shortcuts and global-hotkey behavior, move a built `Peelr.app` to `/Applications` and launch it once so Launch Services registers the app intents.

## Test

```sh
xcodebuild test -project Peelr.xcodeproj -scheme Peelr -configuration Debug -destination 'platform=macOS'
```

Engine changes should include XCTest regression coverage where practical. Prefer small deterministic image fixtures generated in test code over checked-in binary images.

## Optional BiRefNet Model

Peelr runs without BiRefNet and falls back to Vision for photo mode. To bundle the Core ML model locally:

```sh
uv run scripts/convert_birefnet.py --output Resources/BiRefNet.mlpackage
xcodegen generate
xcodebuild -project Peelr.xcodeproj -scheme Peelr -configuration Debug build
```

Do not commit generated Core ML artifacts.

## Conventions

- Use Conventional Commits.
- Keep changes focused and minimal.
- Do not commit `Peelr.xcodeproj`, build products, DerivedData, or generated model artifacts.
