# Changelog

[简体中文](CHANGELOG.md) | **English**

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
