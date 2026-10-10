<p align="center"><img src="assets/appicon.svg" width="128" alt="cliptype"></p>

# cliptype

[简体中文](README.md) | **English**

`cliptype` reads the text on your clipboard and types it into the focused field
character by character as simulated keyboard input — for places where
<kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> doesn't work: remote desktops, VNC, VMs, some
password fields, kiosk software and the like. Runs on **macOS** (native app +
CLI), **Windows** (tray + CLI) and **Linux** (CLI); primarily verified on macOS.

- Two delivery modes: Unicode text events (any character, IME-safe) and real
  key codes (VNC / remote consoles / VMs)
- Three run modes: one-shot with countdown, resident hotkey, status bar / tray
- Native macOS app: menu bar icon, recordable hotkeys, optional local clipboard
  history panel, in-app updates, UI in English / Chinese / Japanese
- Clipboard contents stay local and never appear in logs or errors; the CLI
  makes no network requests

## Install

Packages are on [GitHub Releases](https://github.com/Szyoo/cliptype/releases).

| Platform | File | Notes |
| --- | --- | --- |
| macOS app | `cliptype-vX.Y.Z-macos-app-universal.zip` | Unzip and drag **Cliptype.app** into Applications |
| macOS CLI | `cliptype-vX.Y.Z-aarch64-apple-darwin.tar.gz` / `x86_64-apple-darwin` | Apple Silicon / Intel |
| Windows | `cliptype-vX.Y.Z-x86_64-pc-windows-msvc.zip` | Extract and run |
| Linux | `cliptype-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz` | X11; needs `libxdo` at runtime (`sudo apt-get install -y libxdo3`) |

Every file ships with a `.sha256` checksum. The macOS app and CLI are not
notarized by Apple; clear the quarantine flag before the first run:

```sh
xattr -d com.apple.quarantine /Applications/Cliptype.app   # app
xattr -d com.apple.quarantine ./cliptype                   # CLI
```

The prebuilt CLI includes hotkey and tray modes on macOS / Windows, and hotkey
mode on Linux.

**Build from source** (requires [Rust](https://rustup.rs/); the macOS app also
needs the Xcode command line tools; Linux needs `libxdo-dev` and the xcb
development libraries):

```sh
git clone https://github.com/Szyoo/cliptype && cd cliptype
cargo build --release                    # one-shot mode only
cargo build --release --features tray    # + hotkey + tray (macOS / Windows)
cargo build --release --features hotkey  # + hotkey (any platform)
scripts/bundle-macos.sh                  # macOS app → dist/Cliptype.app
```

## Usage

### Permissions

On macOS, simulated keyboard input requires the **Accessibility** permission
(System Settings → Privacy & Security → Accessibility), granted to the app that
initiates the input:

| How you run it | Grant it to | After granting |
| --- | --- | --- |
| Cliptype.app | **Cliptype** (the bundled engine inherits it) | Relaunch Cliptype |
| `cliptype` in a terminal | Your terminal app (Terminal / iTerm / …) | Quit the terminal with ⌘Q and reopen it |

Without it macOS silently drops the keystrokes; cliptype checks first and exits
with an error. If you upgraded from 0.1.2 or earlier to 0.1.3+ and the switch is
on but nothing works, select Cliptype in the Accessibility list, click **−** to
remove it and **+** to add it again (the app shows these steps itself).
Windows and Linux need no permission.

### macOS app

1. Open Cliptype and follow the first-launch prompt to grant Accessibility.
2. Copy text → focus the target field → press <kbd>⌃⇧V</kbd>.
3. Clipboard history (enable in Settings; off by default): <kbd>⌃⇧H</kbd> opens
   the panel; press 1–9 or ↑↓ + Return to type an item, ⌘Return to copy it.
   History is stored on this Mac only.

Hotkeys, typing speed, remote console mode (VNC / VM), history panel position
and size, and automatic update checks are set in the main window or menu bar
icon → Settings.

### CLI

```sh
cliptype --delay 3000            # switch to the target window within 3 s
cliptype --mode keycode          # VNC / remote consoles / VMs
cliptype --hotkey                # stay resident; type on every ctrl+shift+v
cliptype --hotkey "alt+F9"       # custom combo
cliptype --tray                  # status bar / tray icon (macOS / Windows)
echo -n "text" | cliptype --stdin
```

Resident modes wait for the modifiers to be released before typing;
<kbd>Ctrl</kbd>+<kbd>C</kbd> quits.

## Reference

### Command-line options

| Option | Description | Default |
| --- | --- | --- |
| `-d, --delay <MS>` | Delay before typing starts, in ms (time to focus the target window); ignored in resident modes | `2000` |
| `-i, --interval <MS>` | Delay between keystrokes, in ms; 0 = fastest | `0` |
| `-s, --speed <SPEED>` | Preset: `fast` (0 ms) / `normal` (20 ms) / `slow` (50 ms); conflicts with `--interval` | — |
| `-m, --mode <MODE>` | `unicode`: Unicode text events; `keycode`: real key codes for the current keyboard layout (characters not on the layout fall back to Unicode with a warning; the input source is switched to ASCII while typing) | `unicode` |
| `--dry-run` | Print what would be typed instead of typing it | — |
| `--stdin` | Read the text from standard input instead of the clipboard | — |
| `--check-permission` | Don't type; exit 0 if keystroke simulation is permitted, 1 otherwise | — |
| `--hotkey [COMBO]` | Resident hotkey mode (`hotkey` feature), e.g. `ctrl+shift+v`, `alt+F9` | `ctrl+shift+v` |
| `--tray` | Status bar / tray mode (`tray` feature, macOS / Windows only); combine with `--hotkey` to set the combo | — |
| `-h, --help` / `-V, --version` | Help / version | — |

An empty or non-text clipboard prints a notice and exits normally; errors exit
non-zero.

### Configuration file

Tray-mode settings are stored in `~/.config/cliptype/config.toml`
(`$XDG_CONFIG_HOME/cliptype/` if set, `%APPDATA%\cliptype\` on Windows), one
setting per line:

```toml
interval_ms = 20
keycode_mode = false
```

The macOS app keeps its settings in its own UserDefaults; clipboard history is
stored in `~/Library/Application Support/Cliptype/history.json` (mode 0600).

## License

[MIT](LICENSE)
