# Comet 42

A small macOS menu-bar app for asking AI about the text you select, content you paste, or
screenshots you copy. It also runs one-click presets such as Improve Writing and Change to Email.
It runs on your installed **Claude** or **Codex** command-line tool, so there are no API keys in
the app.

## Quick start
```sh
cd Comet
Scripts/build-app.sh --install    # builds Comet 42.app and copies it to ~/Applications
open ~/Applications/"Comet 42.app"
```

You need macOS 26 or later with the Xcode Command Line Tools, and a signed-in `claude` CLI
(`claude auth login`). Full usage, shortcuts and build notes are in
[Comet/README.md](Comet/README.md).

## Layout
| Path | What it is |
| --- | --- |
| `Comet/Package.swift` | Swift package (no dependencies) |
| `Comet/Sources/Comet/` | App source: `AI/`, `App/`, `Context/`, `HotKey/`, `Presets/`, `Settings/`, `UI/` |
| `Comet/Scripts/build-app.sh` | Builds, signs and optionally installs the `.app` |
| `Comet/Scripts/make-icon.swift` | Draws the app icon; the build regenerates the icon PNG when this file changes |
| `Comet/Resources/AppIcon-1024.png` | Generated icon (committed so a fresh clone builds as is) |

## License
[AGPL-3.0](LICENSE). Third-party copyright notices are in [NOTICE](NOTICE).
