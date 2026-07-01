# Contributing

Peelr is primarily built for Performave's personal workflow and shared in case it helps people with similar needs. Issues and pull requests are welcome, but maintainers may not respond to or address every request.

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/).

Examples:

```text
feat: add batch image export
fix: preserve retina pixel dimensions
docs: clarify BiRefNet setup
test: cover color-key interior protection
```

## Development

Requires Xcode 16+ and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
xcodebuild test -project Peelr.xcodeproj -scheme Peelr -configuration Debug -destination 'platform=macOS'
```

## Pull Requests

Keep changes focused, include tests for behavior changes, and update `CHANGELOG.md` when user-facing behavior changes.
