# Releasing LynxExplorer_iOS

This document defines the minimum release process for this repository.

## Release principles

- Publish only after validating the app against the pinned `lynx` commit.
- Describe what changed for iOS users.
- State known gaps and feature limitations.
- Keep release notes concise and factual.

## Before you release

- Confirm the pinned `lynx` commit is correct in `README.md`.
- Build the homepage bundle from `homepage/`.
- Run `./bundle_install.sh` from `app/`.
- Build the app in Xcode.
- Verify the main flows:
  - Enter URL and open bundle
  - Scan QR code
  - Paste from clipboard
  - Open recent items
  - Return to the homepage

## Versioning

Use iOS-specific tags, for example:

- `v0.1.0-ios`
- `v0.1.1-ios`

## Release note template

Use this format:

```md
## Summary

Short description of the release.

## What's new

- Added ...
- Updated ...
- Fixed ...

## Known limitations

- This repository is iOS-only.
- Feature parity with Android and Harmony is not guaranteed.

## Upstream base

- lynx commit: [`faeec5c7b8e21be2c906d4a9b32d80df596deeb3`](https://github.com/lynx-family/lynx/commit/faeec5c7b8e21be2c906d4a9b32d80df596deeb3)
```

## Publishing checklist

- Update `README.md` if the pinned `lynx` commit changes.
- Update release notes.
- Confirm no generated dependencies are committed:
  - `app/Pods/`
  - `app/LynxExplorer.xcworkspace/`
  - `homepage/node_modules/`
  - `homepage/dist/`
- Tag the release.
- Publish the release notes.
