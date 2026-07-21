# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Clipboard text reading via `arboard`; empty or non-text clipboard exits gracefully.
- Keystroke sending via `enigo`: fast mode (batched `text()`) when `--interval` is 0,
  per-character mode with configurable delay otherwise.
- Newlines and tabs are sent as real Return/Tab key presses for better app compatibility.
- Line endings are normalized to LF before typing (CRLF/CR from Windows clipboards
  no longer produce double newlines).
- On macOS, keyboard errors include a hint to grant the Accessibility permission.
- Initial project scaffold: Cargo manifest, module layout (`cli`, `clipboard`, `typer`), README, MIT license.
- Cross-platform CI (macOS / Windows / Linux) with fmt, clippy, build, and test.

### Changed
- All user-facing CLI messages and `--help` text are now in English.
