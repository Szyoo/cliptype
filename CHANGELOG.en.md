# Changelog

[简体中文](CHANGELOG.md) | **English**

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Clipboard history panel**: a hotkey (⌃⇧H by default; ⌃⌥H / ⌘⇧H available)
  opens a floating panel listing recent items numbered 1–9. Press a digit or
  ↑↓ + Return to **type the item straight into the focused field** (the
  clipboard is left alone); ⌘Return copies it instead; type to filter; Esc or
  clicking elsewhere closes it. The panel never steals focus from the target
  app. Four positions: **below the menu bar icon (default)**, near the text
  cursor (falls back to the icon when the app doesn't expose the cursor — VNC,
  remote desktops, VMs), screen center, and **custom** (drag the panel
  anywhere; the position is saved on release and can be reset). Requires
  clipboard history to be enabled in Settings.
- **Record your own shortcuts**: both hotkeys (type clipboard, history panel)
  are no longer limited to presets — click the shortcut button and press any
  combination (at least one of ⌃⌥⇧⌘). A clear message appears if another app
  already owns it, and one click restores the default. Presets chosen in
  earlier versions are migrated automatically.
- The history panel's item count is configurable (3–9, default 9); the digit
  shortcuts and the panel height follow it.

## [0.1.3] - 2026-09-13

### Changed
- **The macOS app is now signed with a stable code-signing certificate**: the
  signing requirement no longer changes with every build, so **the Accessibility
  permission survives in-app updates — no more re-granting**. Upgrading from
  0.1.2 or earlier (ad-hoc signed) still requires one re-grant (remove the entry
  and add it again); after that it sticks. The update helper no longer resets
  the permission record. The app is still not notarized by Apple, so the
  Gatekeeper warning remains.
- The main and settings windows can now be resized down to about 440×360 and
  the form scrolls when the content is taller; previously the window was forced
  to the full content height and could not be made smaller. Default size is
  480×640.

### Added
- **Clipboard history (basic, off by default)**: once enabled in Settings, the
  macOS app records the text you copy (deduplicated, capped at 20/50/100 items,
  100 KB per item), stored only on this Mac in the Application Support folder
  (mode 0600); items that password managers mark as concealed or transient are
  skipped. A "Clipboard history" submenu in the menu bar lists recent items —
  pick one to put it back on the clipboard, then type it with the hotkey. The
  full history UI (popup panel etc.) will be decided in a later version.
- CLI: `--stdin` reads the text to type from standard input instead of the
  clipboard (used by the app to type a history item; the text never appears in
  the process arguments).

## [0.1.2] - 2026-09-11

### Fixed
- **Permission status never updated**: `AXIsProcessTrusted()` is cached per
  process, so a running app could never observe the permission being granted
  or revoked — users who had just granted it still saw "Accessibility
  permission required". The app now asks a fresh process (the bundled engine's
  `--check-permission`), so the UI updates within 2 seconds of granting, no
  relaunch needed.
- **Switch enabled after an update but nothing works**: an in-app update
  replaces the whole bundle, and macOS ties the old permission record to the
  previous version's signature; toggling the switch off and on doesn't help —
  the entry has to be removed and re-added (found via a user report). If the
  permission is still missing 12 seconds after an update, the app now shows the
  exact − / + steps with a "Remove the entry for me" button; the same guidance
  lives permanently in the Settings permission section.
- Opening System Settings tries several URL schemes in order, for compatibility
  across macOS versions.

### Added
- CLI: `--check-permission` reports via the exit code whether keystroke
  simulation is permitted (0 = allowed) without typing anything; used by the
  macOS app to query the permission state.

## [0.1.1] - 2026-09-11

### Added
- **`--mode keycode` (remote console mode)**: presses real key codes per
  character according to the current keyboard layout (adding Shift/Option when
  needed) instead of sending Unicode text events. Fixes VNC, remote console and
  VM targets, which **typed every character as `a`** because they forward only
  physical key codes and ignore attached Unicode text. The input source is
  switched to an ASCII layout while typing so input methods don't intercept the
  keys, then restored. Characters not on the layout fall back to Unicode text
  with a one-time warning.
- "Remote console mode (VNC / VM)" toggle in the macOS app (Settings and the
  menu bar menu) and in the tray menu, persisted alongside the other settings.
- **In-app updates for the macOS app**: checks GitHub Releases on launch and
  every 24 hours (can be disabled), shows the release notes, downloads the
  universal app archive, verifies its SHA-256, then replaces the bundle and
  relaunches. "Check for Updates…" is available from the menu bar menu and
  Settings.
- App icon.
- The version is shown in the app (menu bar title, main window header,
  Settings).

## [0.1.0] - 2026-08-07

First release. Fully verified on macOS (one-shot, hotkey, tray and native app);
the Windows and Linux builds are CI-tested, with runtime verification pending.

### Added
- Clipboard text reading via `arboard`; an empty or non-text clipboard exits
  gracefully.
- Keystroke sending via `enigo`: batched fast mode when `--interval` is 0,
  per-character mode with a configurable delay otherwise.
- Newlines and tabs are sent as real Return/Tab key presses for better app
  compatibility.
- Line endings are normalized to LF before typing (CRLF/CR from Windows
  clipboards no longer produce double newlines).
- `--speed fast|normal|slow` typing speed presets as a friendlier alternative
  to `--interval`.
- **Resident hotkey mode** (`--features hotkey`): `cliptype --hotkey [COMBO]`
  stays running and types the current clipboard on every press (default combo
  `ctrl+shift+v`). It waits for the hotkey's modifier keys to be released
  before typing, so the combo does not contaminate the output.
- **Status bar / tray mode** (`--features tray`, macOS & Windows):
  `cliptype --tray` shows a native status bar icon with the active hotkey,
  pause/resume and typing speed presets. Speed changes persist to a config file
  and are restored on the next launch. Each platform's binary contains only its
  own UI code; Linux builds don't include the tray.
- **Native macOS app**: main window plus resident menu bar, with the UI
  localized in Chinese, English and Japanese.
- On macOS, a missing Accessibility permission is detected up front and the app
  exits with clear guidance, instead of appearing to succeed while the OS
  silently discards every keystroke.
- Release workflow: tags build and attach prebuilt artifacts — the macOS app
  (universal) plus CLI builds for macOS (Apple Silicon & Intel), Windows and
  Linux, each with a SHA-256 checksum.
- Cross-platform CI (macOS / Windows / Linux) with fmt, clippy, build and test.

### Changed
- All user-facing CLI messages and `--help` text are now in English.

### Fixed
- Trailing characters could be lost when the process exited before the last
  keyboard events were delivered; cliptype now waits briefly before exiting.
- Per-character mode (`--interval > 0`) was intercepted by input methods,
  mangling CJK text and dropping emoji; it now uses the same IME-transparent
  event mechanism as the fast path.
