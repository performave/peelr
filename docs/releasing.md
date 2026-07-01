# Releasing

Peelr releases are produced by the [`release` workflow](../.github/workflows/release.yml). Releases are cut only by pushing a valid SemVer tag.

Read [CI setup](ci-setup.md) first if signed and notarized releases have never run for this repo.

## TL;DR

```sh
# 1. Update CHANGELOG.md with a section like: ## [1.2.3]
# 2. Commit the release prep.
# 3. Tag and push:
git tag v1.2.3
git push origin v1.2.3
```

## Versioning

Release tags must be SemVer with a leading `v`:

```text
v1.2.3
v1.2.3-beta.1
v1.2.3+build.1
```

The workflow rejects non-SemVer tags before building. There is no manual publish path; if a release fails, fix the workflow or release inputs and push a new tag.

## Changelog Requirement

Every release must have a matching `CHANGELOG.md` section:

```md
## [1.2.3]

### Added

- New release note.
```

The workflow validates that section exists, then extracts that section with a small auditable shell step and uses it as the GitHub Release body. If the section is missing or empty, the release fails.

## What the Workflow Does

On a valid release tag, the workflow:

1. Validates the SemVer tag.
2. Checks out the tag.
3. Installs XcodeGen.
4. Imports the Developer ID Application certificate.
5. Generates the Xcode project.
6. Builds `Peelr.app` in Release configuration.
7. Signs the app with hardened runtime and timestamp.
8. Notarizes and staples the app.
9. Zips `Peelr.app` and writes a `.sha256` checksum.
10. Extracts release notes from `CHANGELOG.md` and creates a GitHub Release using those notes as the body.
11. Updates the `peelr` cask in `Performave/homebrew-tap` if `HOMEBREW_TAP_TOKEN` is configured.

## Homebrew Cask

Peelr is distributed as a cask in [`Performave/homebrew-tap`](https://github.com/Performave/homebrew-tap):

```sh
brew install --cask Performave/tap/peelr
```

The release workflow updates `Casks/peelr.rb` with the release URL, version, and SHA-256 checksum. It commits that change to the tap as `github-actions[bot]`.

## Failed Releases

Do not publish a release manually. Fix the failing workflow, signing input, changelog entry, or tag, then rerun by pushing a corrected release tag.
