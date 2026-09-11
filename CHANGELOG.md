# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `--mode keycode`: press real key codes per character (looked up from the
  current keyboard layout, with Shift/Option as needed) instead of Unicode text
  events. Fixes VNC / remote console / VM targets, which ignore attached
  Unicode text and typed every character as `a`. The input source is switched
  to an ASCII layout while typing so IMEs don't intercept the keys, then
  restored. Characters not on the layout fall back to Unicode with a warning.
- "Remote console mode (VNC / VM)" toggle in the macOS app (settings + menu bar
  menu) and in the tray menu; persisted alongside the other settings.
- In-app updates for the macOS app: checks GitHub Releases on launch and every
  24 hours (can be disabled), shows the release notes, downloads the universal
  app archive, verifies its SHA-256, then replaces the bundle and relaunches.
  "Check for Updates…" is available from the menu bar menu and Settings.
- App icon.

## [0.1.0] - 2026-08-07

### Added
- `--speed fast|normal|slow` typing speed presets as a friendlier alternative
  to `--interval`.
- Release workflow: tags build and attach prebuilt binaries for macOS
  (Apple Silicon & Intel), Windows, and Linux with SHA-256 checksums.
- Clipboard text reading via `arboard`; empty or non-text clipboard exits gracefully.
- Keystroke sending via `enigo`: fast mode (batched `text()`) when `--interval` is 0,
  per-character mode with configurable delay otherwise.
- Newlines and tabs are sent as real Return/Tab key presses for better app compatibility.
- Line endings are normalized to LF before typing (CRLF/CR from Windows clipboards
  no longer produce double newlines).
- On macOS, keyboard errors include a hint to grant the Accessibility permission.
- Initial project scaffold: Cargo manifest, module layout (`cli`, `clipboard`, `typer`), README, MIT license.
- Cross-platform CI (macOS / Windows / Linux) with fmt, clippy, build, and test.

- On macOS, cliptype now detects a missing Accessibility permission up front and
  exits with clear guidance, instead of appearing to succeed while the OS
  silently discards every keystroke.
- Resident hotkey mode (`--features hotkey`): `cliptype --hotkey [COMBO]` stays
  running and types the current clipboard on every press (default combo
  `ctrl+shift+v`). Waits for the hotkey's modifier keys to be released before
  typing so the combo does not contaminate the output.
- Status bar / tray mode (`--features tray`, macOS & Windows): `cliptype --tray`
  shows a native status bar icon with the active hotkey, pause/resume, and
  typing speed presets. Speed changes persist to a config file and are restored
  on the next launch. Each platform's binary contains only its own UI code;
  Linux builds don't include the tray.

### Changed
- All user-facing CLI messages and `--help` text are now in English.

### Fixed
- Trailing characters could be lost when the process exited before the last
  keyboard events were delivered; cliptype now waits briefly before exiting.
- Per-character mode (`--interval > 0`) was intercepted by active input methods
  (IMEs), mangling CJK text and dropping emoji; it now uses the same
  IME-transparent event mechanism as the fast path.
