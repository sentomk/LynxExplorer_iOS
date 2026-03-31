# LynxExplorer_iOS

LynxExplorer_iOS is an iOS-only fork of Lynx Explorer.

This repository is based on the `lynx` source tree at commit [`faeec5c7b8e21be2c906d4a9b32d80df596deeb3`](https://github.com/lynx-family/lynx/commit/faeec5c7b8e21be2c906d4a9b32d80df596deeb3).

## Scope

- Build and run the Lynx Explorer iOS app.
- Maintain the homepage bundle used by the iOS app.
- Publish iOS-focused changes without requiring feature parity with Android, Harmony, Windows, or macOS.

## Repository layout

- `app/`: Native iOS application sources.
- `homepage/`: ReactLynx homepage bundle sources.
- `docs/`: Writing and release guidance for this repository.

## Prerequisites

- macOS with Xcode 15.0 or later
- Ruby and Bundler
- Python 3.9 or later
- Node.js and pnpm
- A local `lynx` checkout pinned to commit `faeec5c7b8e21be2c906d4a9b32d80df596deeb3`

## Set up the Lynx dependency

Clone `lynx` next to this repository, or point `LYNX_ROOT` to an existing checkout.

```bash
cd ~/Code
git clone https://github.com/lynx-family/lynx.git lynx
git -C lynx checkout faeec5c7b8e21be2c906d4a9b32d80df596deeb3
```

If you keep `lynx` elsewhere, export `LYNX_ROOT` before running the setup script.

```bash
export LYNX_ROOT=/path/to/lynx
```

## Build the app

1. Install homepage dependencies and generate the homepage bundle.
2. Generate the Lynx podspecs from the pinned `lynx` checkout.
3. Install CocoaPods dependencies.
4. Open the workspace in Xcode.

```bash
cd app
./bundle_install.sh
open LynxExplorer.xcworkspace
```

## Run on a device

Open `LynxExplorer.xcworkspace` in Xcode, choose the `LynxExplorer` scheme, configure signing, and run the app on a simulator or a physical device.

## Documentation standards

Repository documentation follows the Google developer documentation style guide:

- Write for task completion.
- Use short headings and short paragraphs.
- Prefer direct instructions and concrete prerequisites.
- Keep release notes factual and easy to scan.

See [docs/STYLE.md](docs/STYLE.md) and [docs/RELEASING.md](docs/RELEASING.md).
