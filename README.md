# ClipStack

A modern, Apple Silicon–native clipboard manager for the menu bar, inspired by
[ClipMenu](https://github.com/naotaka/ClipMenu) by Naotaka Morimoto (the
classic clipboard manager last released in 2009 for PowerPC/Intel Macs).
ClipStack is a from-scratch reimplementation in Swift 6, AppKit, and SwiftUI —
no code or assets from the original. Requires macOS 13+.

*Named ClipStack (not "ClipMenu") per the original author's request that
derived works not reuse the ClipMenu name.*

## Features

- **Clipboard history** in the menu bar — text (with rich-text fidelity),
  images, and copied files.
- **Inline items + numbered folders** — the first N clips appear inline, the
  rest in `11 - 20`-style submenus.
- **Number-key shortcuts** (1–9, 0) to select items while a menu is open.
- **Snippets** — user-defined text in folders, managed in a Snippet Editor
  window and shown at the bottom of the menu. Auto-pastes on selection
  (toggleable).
- **Global hotkeys** — ⌘⇧V pops the history menu at the mouse cursor, ⌘⇧B pops
  the snippets menu. Both are re-recordable in Preferences.
- **Actions** — text transforms applied to the current clipboard (change case,
  Base64, URL/HTML encode, MD5/SHA hashes, whitespace cleanup, reverse…).
  Custom JavaScript actions are supported: drop `.js` files into
  `~/Library/Application Support/ClipStack/actions/` — each script gets the
  clipboard text as `clipText` and returns the transformed string (the same
  contract as classic ClipMenu action scripts).
- **Snippet import** — menu → Import Snippets… reads classic ClipMenu XML
  exports and ClipStack JSON backups.
- **Automatic backups to Google Drive** — snippets and history are backed up
  daily into the Google Drive for desktop sync folder
  (`My Drive/ClipStack Backups`), keeping the 14 most recent. Configure or run
  on demand in Preferences → Backup.
- **Preferences** — history size, inline/folder counts, title length,
  thumbnails, tooltips, persistence, excluded apps, launch at login, hotkeys.

## Modern niceties

- Native **arm64**; no deprecated frameworks.
- **Password-manager aware**: clipboard content marked concealed/transient
  (the `org.nspasteboard.*` convention) is never recorded (toggleable).
- **Launch at login** via `SMAppService` — appears properly in
  System Settings → General → Login Items.
- **Paste automatically** sends ⌘V to the frontmost app; requires the
  Accessibility permission (prompted on first use).
- History and snippets persist as plain JSON in
  `~/Library/Application Support/ClipStack/`.

## Building

```
./build.sh
```

Produces `ClipStack.app`. With only Command Line Tools installed the binary is
native-arch (arm64 on Apple Silicon); with full Xcode installed the script
builds a universal arm64 + x86_64 binary automatically.

The script signs with a `ClipMenu Dev` code-signing certificate if one exists
in your keychain (recommended — keeps macOS permission grants stable across
rebuilds), otherwise falls back to ad-hoc signing.

The app icon is drawn programmatically: see `Bundle/draw_icon.swift`.

## Credits

Functionality modeled on **ClipMenu** by Naotaka Morimoto (MIT licensed,
open-sourced 2015). This project shares no code with it — it is an homage and
a modern replacement.

## License

MIT — see [LICENSE](LICENSE).
