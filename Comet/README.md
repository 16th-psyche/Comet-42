# Comet 42

A macOS menu-bar app for asking AI about selected text, pasted content and screenshots. It runs on your
installed **Claude** or **Codex** CLI, so there are no API keys and no login in the app.

## Use
1. Select text in any app, or copy a screenshot (`⌃⇧⌘4`).
2. Press **⌥Space** (you can change it in Settings).
3. Type a question and press ↩, or click a preset (`⌘1`–`⌘9`).
4. Use the result:
   - **Replace** (`⌘↩`) pastes it over your selection.
   - **Copy** (`⌘⇧C`) copies it.
   - `⌘N` starts a new chat. Esc closes the panel.

The first six presets are Improve Writing, Fix Spelling and Grammar, Explain This in Simple
Terms, Change Tone to Professional, Change Tone to Friendly, and Change to Email. To add, edit,
reorder presets, or have one replace the selection straight away, use Settings → Presets.

## Pasting content
Selection isn't the only input. Press **⌘V** in the panel, or click **Paste**:
- **Screenshot or image:** becomes an image chip.
- **Long text:** becomes a "Pasted text" chip.
- **Short text:** goes into the question box.
- **Files:** text, code, PDF and image files become chips.

You can also drag files, images or text onto the panel.

## Moving and resizing
- **Move:** drag the title bar.
- **Resize:** drag any edge (the grip is bottom-right). Size and position are remembered.
- **Reset size and position:** double-click the title bar, or press ⌘⌥0.
- **Text size:** ⌘+ / ⌘− / ⌘0, the **AA** menu, or Settings → Panel.
- **Keep the panel open:** the pin button stops it hiding when you click elsewhere.
- **Close:** Esc or ⌘W.
- **Accessibility:** VoiceOver labels every control and announces when an answer is ready. Reduce
  Transparency and Increase Contrast switch the panel to an opaque, high-contrast style.

## Build
```
Scripts/build-app.sh --install   # builds build/Comet 42.app and copies it to ~/Applications
.build/debug/Comet --selftest  # runs a real Claude round trip from the terminal
```

## Requirements
- macOS 26 or later, and the Command Line Tools (full Xcode is not required).
- `claude` signed in (`claude auth login`). For Codex: `npm i -g @openai/codex`, then `codex login`.
- Accessibility permission, to read the selection and paste results back.
- Optional: a "Comet Local Signing" certificate in your login keychain. The build script uses it
  when present, so the Accessibility permission survives rebuilds.

Licensed under the AGPL-3.0; see ../LICENSE and ../NOTICE.
