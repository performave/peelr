# CI Setup

This is the one-time setup required for the test and release workflows.

## Test Workflow

The [`test` workflow](../.github/workflows/test.yml) runs on pushes and pull requests. It installs XcodeGen, generates the Xcode project, and runs:

```sh
xcodebuild test -project Peelr.xcodeproj -scheme Peelr -configuration Debug -destination 'platform=macOS'
```

No secrets are required for tests.

## Release Workflow Requirements

The [`release` workflow](../.github/workflows/release.yml) builds, signs, notarizes, publishes a GitHub Release, and updates the Homebrew cask. It requires an Apple Developer Program membership and repo admin access to configure secrets.

## Apple Signing Certificate

Create or download a **Developer ID Application** certificate using Xcode or Keychain Access.

Export the certificate and its private key as a `.p12`, then record the exact signing identity:

```sh
security find-identity -v -p codesigning
```

The identity should look like:

```text
Developer ID Application: Performave (TEAMID)
```

## App Store Connect API Key

Use an App Store Connect API key for notarization.

1. Open <https://appstoreconnect.apple.com>.
2. Go to **Users and Access** -> **Integrations** -> **App Store Connect API**.
3. Generate a key with the **Developer** role.
4. Record the Key ID and Issuer ID.
5. Download the `AuthKey_XXXXXXXX.p8` file. It can only be downloaded once.

## GitHub Actions Secrets

Add these secrets in the Peelr repo under **Settings** -> **Secrets and variables** -> **Actions**.

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE` | Base64 of the exported `.p12`, for example `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` |
| `APPLE_SIGNING_IDENTITY` | Full Developer ID identity |
| `APPLE_API_KEY` | App Store Connect Key ID |
| `APPLE_API_ISSUER` | App Store Connect Issuer ID |
| `APPLE_API_PRIVATE_KEY` | Raw contents of `AuthKey_XXXX.p8`, including BEGIN and END lines |
| `HOMEBREW_TAP_TOKEN` | Fine-grained PAT with `contents:write` on `Performave/homebrew-tap` |

Using `gh`:

```sh
gh secret set APPLE_CERTIFICATE < <(base64 -i cert.p12)
gh secret set APPLE_CERTIFICATE_PASSWORD --body 'the-p12-password'
gh secret set APPLE_SIGNING_IDENTITY --body 'Developer ID Application: Performave (TEAMID)'
gh secret set APPLE_API_KEY --body 'ABC123DEF4'
gh secret set APPLE_API_ISSUER --body '00000000-0000-0000-0000-000000000000'
gh secret set APPLE_API_PRIVATE_KEY < AuthKey_ABC123DEF4.p8
gh secret set HOMEBREW_TAP_TOKEN --body 'github_pat_...'
```

## Homebrew Tap Token

Use a fine-grained PAT named something like `peelr-release-homebrew-tap`.

Recommended settings:

- Resource owner: `Performave`
- Repository access: only `homebrew-tap`
- Repository permissions: `Contents` read and write

The workflow stores this as `HOMEBREW_TAP_TOKEN` and uses it to clone and push to `Performave/homebrew-tap`. If the secret is missing, the release still publishes but the cask bump is skipped.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Certificate import fails | Bad `.p12` base64 or wrong export password |
| `codesign` cannot find identity | `APPLE_SIGNING_IDENTITY` does not match `security find-identity` exactly |
| Notarization auth fails | Wrong App Store Connect key, issuer, or incomplete `.p8` content |
| Release stops before publishing | Tag is not SemVer or `CHANGELOG.md` lacks a matching release section |
| Cask is not updated | `HOMEBREW_TAP_TOKEN` is missing or lacks write access to `Performave/homebrew-tap` |
