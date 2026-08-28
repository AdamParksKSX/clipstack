# ClipStack

A modern, Apple Silicon–native clipboard manager for the menu bar, inspired by
[ClipMenu](https://github.com/naotaka/ClipMenu) by Naotaka Morimoto (the
classic clipboard manager last released in 2009 for PowerPC/Intel Macs).
ClipStack is a from-scratch reimplementation in Swift 6, AppKit, and SwiftUI —
no code or assets from the original. Requires macOS 13+.


## What's new in 1.3.2

- Preference pane captions now wrap reliably; the History pane no longer
  overflows the window (completing the fix attempted in 1.3.1). All panes
  are verified to fit via a new dev tool: `ClipStack --render-prefs <dir>`
  renders each pane to a PNG with its measured width.

## What's new in 1.3.1

- Fixed the History preferences pane being clipped at the window edges.
  Explanatory captions in all preference panes now wrap instead of widening
  the window.

## What's new in 1.3.0

- **Auto-delete old history items** — a new "Delete items automatically"
  setting in Preferences → History removes clips older than a chosen period
  (1 hour, 6 hours, 1 day, 1 week, or 1 month; default Never). Favourites
  are never deleted.

## What's new in 1.2.1

- Daily backups now contain only snippets; clipboard history is no longer
  copied to the backup folder.

## What's new in 1.2.0

- **Favourites** — star any history item to pin it to the top of the menu;
  favourites never age out of the history and survive Clear History.
- **Edit clips** — fix up a text clip in place via an edit dialog.
- **Delete clips** — remove single items; the menu stays open so several can
  be cleaned up in a row.
- All three live as **★ / ✎ / ✕ buttons on each history row** (in the style
  of Clipboard History Pro). Clicking anywhere else on a row pastes it, and
  number-key shortcuts and keyboard navigation work as before.
- Preferences window widened so the Shortcuts pane labels aren't clipped.

Older changes are on the
[Releases](https://github.com/AdamParksKSX/clipstack/releases) page.

## Features

- **Clipboard history** in the menu bar — text (with rich-text fidelity),
  images, and copied files.
- **Inline items + numbered folders** — the first N clips appear inline, the
  rest in `11 - 20`-style submenus.
- **Favourites, editing, and deleting** — every history item has inline
  **★ favourite**, **✎ edit** (text clips), and **✕ delete** buttons on the
  right of its row. Favourites are pinned to the top of the menu, never age
  out of the history, and survive Clear History.
- **Number-key shortcuts** (1–9, 0) to select items while a menu is open.
- **Snippets** — user-defined text in folders, managed in a Snippet Editor
  window and shown at the bottom of the menu. Auto-pastes on selection
  (toggleable).
- **Global hotkeys** — ⌘⇧V pops the history menu at the mouse cursor, ⌘⇧B pops
  the snippets menu, ⌘⇧E / ⌘⇧D encode/decode the clipboard as Base64. All are
  re-recordable in Preferences.
- **Actions** — transforms applied to the current clipboard text; the result
  replaces the clipboard and is added to the history. Currently trimmed to
  **Encode to Base64** and **Decode from Base64**; custom JavaScript actions
  are still supported — drop `.js` files into
  `~/Library/Application Support/ClipStack/actions/` (create it if needed) —
  each script gets the clipboard text as `clipText` and returns the
  transformed string (the same contract as classic ClipMenu action scripts).
- **Snippet import** — menu → Import Snippets… reads classic ClipMenu XML
  exports, ClipStack JSON backups, and Text Blaze folder exports (JSON).
  Text Blaze dynamic `{commands}` are imported as literal text.
- **Automatic backups to Google Drive** — snippets are backed up
  daily into the Google Drive for desktop sync folder
  (`My Drive/ClipStack Backups`), keeping the 14 most recent. Configure or run
  on demand in Preferences → Backup.
- **Auto-delete** — optionally remove history items older than a chosen
  period (1 hour to 1 month) in Preferences → History; favourites are exempt.
- **Preferences** — history size, auto-delete period, inline/folder counts,
  title length, thumbnails, tooltips, persistence, excluded apps, launch at
  login, hotkeys.

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
- **Self-updating** — once a week the app checks GitHub Releases, downloads a
  newer build, verifies it is signed with the same certificate before
  installing, and offers to relaunch. Toggleable in Preferences → General
  ("Check for Updates Now" lives there too). Anonymous API access means this
  works while the repository is public; on a private repo checks are skipped.

## Installing

Download the latest `ClipStack-x.y.z.dmg` from
[Releases](https://github.com/AdamParksKSX/clipstack/releases), open it, and
drag ClipStack to Applications.

ClipStack is not notarized with Apple (no paid developer account), so the
first launch is blocked by Gatekeeper. To approve it once:

1. Open ClipStack — macOS shows a "not opened" warning; close it.
2. Go to **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway** next to the ClipStack message, then confirm.

Alternatively, clear the quarantine flag in Terminal:

```
xattr -d com.apple.quarantine /Applications/ClipStack.app
```

To enable automatic paste, grant the Accessibility permission when prompted
(System Settings → Privacy & Security → Accessibility).

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
`./dist.sh` builds and packages a drag-to-install DMG (plus a zip) in `dist/`.

## Credits

Functionality modeled on **ClipMenu** by Naotaka Morimoto (MIT licensed,
open-sourced 2015). This project shares no code with it — it is an homage and
a modern replacement.

## License

MIT — see [LICENSE](LICENSE).
