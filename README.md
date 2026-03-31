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
- Git
- Ruby and Bundler
- Python 3.9 or later
- PyYAML for Python
- Node.js, Corepack, and pnpm

## Clone the upstream Lynx source tree

LynxExplorer_iOS is not a fully standalone runtime repository. Before you build the app, clone the upstream `lynx` repository and check out the required commit.

```bash
cd ~/Code
git clone https://github.com/lynx-family/lynx.git
git -C lynx checkout faeec5c7b8e21be2c906d4a9b32d80df596deeb3
```

## Set up the Lynx dependency

Set `LYNX_ROOT` to the local `lynx` checkout before running the setup script.

```bash
export LYNX_ROOT=~/Code/lynx
```

If you keep `lynx` elsewhere, point `LYNX_ROOT` to that path instead.

## Initialize the repository

Run the bootstrap script from the repository root.

```bash
./bootstrap.sh
```

The script validates the local build environment before you install iOS dependencies. It checks:

- Git, Xcode, and Command Line Tools
- Python 3.9 or later and the `yaml` module
- Ruby, Bundler, Node.js, Corepack, and pnpm
- `LYNX_ROOT`, the required upstream files, and the pinned `lynx` commit

## Build the app

After `bootstrap.sh` passes, install the homepage bundle and CocoaPods dependencies.

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
