# Comet 42: developer notes

What the app does, plus setup and usage, is in the [main README](../README.md). This page covers
working on the code.

## Build and run

```sh
swift build                       # compile (Command Line Tools are enough; Xcode not required)
.build/debug/Comet --selftest     # one real request through the Claude CLI, no UI
Scripts/build-app.sh              # package "build/Comet 42.app" (icon, Info.plist, signing)
Scripts/build-app.sh --install    # …and replace ~/Applications/"Comet 42.app"
```

Add `codex` to the self-test (`--selftest codex`) to exercise the Codex CLI instead.

## README screenshots

`--demo` opens one sample screen with built-in example content. It saves nothing, registers no
hotkey and doesn't touch a running copy of the app, so it's safe to run while you use Comet 42:

```sh
.build/debug/Comet --demo rewrite            # also: chat, context, settings; add --light for light mode
```

It prints `WINDOW <number>`. Capture that window with `screencapture -l <number> out.png`, and save
both themes to `docs/screenshots/<shot>-dark.png` and `<shot>-light.png`.

## Signing

`build-app.sh` signs with a keychain identity named **Comet Local Signing** when one exists, so
macOS keeps the Accessibility permission across rebuilds. Without it the app is signed ad hoc, and
you'll need to toggle the permission off and on after each rebuild.

## Where things live

- **Settings:** `UserDefaults` (`in.quantumleap.comet`, key `CometSettings`).
- **Presets:** `~/Library/Application Support/Comet/presets.json`. The built-ins in
  `Sources/Comet/Presets/Preset.swift` apply only until the reader saves their own list.
- **App icon:** drawn by `Scripts/make-icon.swift`. The build redraws `Resources/AppIcon-1024.png`
  when the script is newer.

## Conventions

- Swift 6 language mode with `MainActor` as the default isolation. Process IO and stream decoding
  run off the main actor in `nonisolated` types.
- No third-party dependencies, and no API keys: every model call goes through an installed CLI.

Licensed under the AGPL-3.0. See [LICENSE](../LICENSE) and [NOTICE](../NOTICE).
