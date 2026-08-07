# cliptype

[简体中文](README.md) | **English**

Type the contents of your clipboard as simulated keystrokes.

`cliptype` reads whatever text is on your clipboard and "types" it out character
by character as real keyboard input. This is useful for fields that block
paste — remote desktop sessions, VMs, some password prompts, kiosk software, and
similar environments where <kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> simply doesn't work.

Cross-platform: **macOS** (native app + CLI), **Windows** (tray + CLI), and
**Linux** (CLI).

> Status: implemented and verified on macOS; Windows/Linux runtime verification
> is in progress. See the [Roadmap](#roadmap).

## Install

All packages are on the [GitHub Releases](https://github.com/Szyoo/cliptype/releases)
page. On macOS there are two ways to use cliptype — **pick either one**:

### macOS · Option 1: install the app (recommended)

GUI + resident menu bar icon, best for everyday use.

1. Download `cliptype-vX.Y.Z-macos-app-universal.zip` (runs on both
   Apple Silicon and Intel).
2. Unzip and drag **Cliptype.app** into your Applications folder.
3. The app is not developer-signed yet — clear the quarantine flag before the
   first launch:

   ```sh
   xattr -d com.apple.quarantine /Applications/Cliptype.app
   ```

4. Open Cliptype. On first launch it walks you through granting the permission:
   go to **System Settings → Privacy & Security → Accessibility** and enable
   **Cliptype** (this single entry also covers the bundled typing engine).
5. Copy some text → focus the target field → press <kbd>⌃⇧V</kbd>.
   The hotkey and typing speed are configurable in the main window or via the
   menu bar icon → Settings.

### macOS · Option 2: terminal CLI

No GUI — for developers and scripting.

1. Download `cliptype-vX.Y.Z-aarch64-apple-darwin.tar.gz` (Apple Silicon) or
   `x86_64-apple-darwin` (Intel) and extract the `cliptype` binary.
2. Clear the quarantine flag: `xattr -d com.apple.quarantine ./cliptype`
3. The permission goes to **the terminal app that runs it**: in System
   Settings → Accessibility, add and enable Terminal / iTerm / whatever you
   actually use, then **fully quit and reopen the terminal**.
4. See [CLI usage](#cli-usage) below.

> The two grants are independent: the app option authorizes Cliptype itself,
> the CLI option authorizes your terminal. Without the permission macOS
> silently discards simulated keystrokes; cliptype detects this and exits with
> an error instead of pretending to succeed.

### Windows

Download `cliptype-vX.Y.Z-x86_64-pc-windows-msvc.zip` and extract
`cliptype.exe` — no extra setup. `cliptype.exe --tray` starts the resident
tray mode.

### Linux

Download `cliptype-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz` and extract (X11;
Wayland depends on your compositor, XWayland generally works). Requires
`libxdo` at runtime:

```sh
sudo apt-get install -y libxdo3   # Debian/Ubuntu runtime
```

### Build from source

Requires a [Rust toolchain](https://rustup.rs/); the macOS app additionally
needs the Xcode command line tools.

```sh
git clone https://github.com/Szyoo/cliptype
cd cliptype
cargo build --release            # CLI, binary at target/release/cliptype
scripts/bundle-macos.sh          # macOS app, output at dist/Cliptype.app
```

Linux build dependencies: `libxdo-dev` and the xcb development libraries (see
the CI config).

## CLI usage

```
cliptype [OPTIONS]

Options:
  -d, --delay <MS>      Delay before typing starts, in ms  [default: 2000]
  -i, --interval <MS>   Delay between keystrokes, in ms     [default: 0]
  -s, --speed <SPEED>   Typing speed preset  [possible values: fast, normal, slow]
      --dry-run         Print what would be typed instead of typing it
  -h, --help            Print help
  -V, --version         Print version
```

`--speed` is a friendlier alternative to `--interval` (fast = no delay,
normal = 20 ms, slow = 50 ms — for apps that drop keys at full speed).

```sh
# Copy some text, then:
cliptype --delay 3000
# Switch to the target window within 3s; the clipboard text is typed in.
```

### Resident hotkey mode (`--features hotkey`)

`cliptype --hotkey` stays resident and types the current clipboard every time
you press the hotkey — no countdown:

```sh
cliptype --hotkey                    # default combo: ctrl+shift+v
cliptype --hotkey "alt+F9"           # custom combo
cliptype --hotkey --interval 20      # per-character typing on each press
```

It waits until the modifiers are released before typing, so the combo doesn't
contaminate the output. Press <kbd>Ctrl</kbd>+<kbd>C</kbd> in the terminal to
quit.

### Status bar / tray mode (`--features tray`, macOS & Windows)

`cliptype --tray` adds a status bar icon on top of the hotkey mode: shows the
active hotkey, pause/resume, speed switching (persisted to
`~/.config/cliptype/config.toml`, `%APPDATA%\cliptype\` on Windows). For
everyday macOS use, prefer the native app (Option 1).

## Roadmap

- [x] Clipboard read & keystroke sending (Unicode / newline / tab, verified on macOS)
- [ ] Windows / Linux runtime verification
- [x] Resident hotkey mode (`--features hotkey`)
- [x] Status bar / tray UI (`--features tray`, macOS & Windows)
- [x] Native macOS app (main window + menu bar, UI in en/zh-Hans/ja)
- [x] Prebuilt releases: CLI for three platforms + macOS app (universal)
- [ ] App signing & notarization (once an Apple Developer certificate is set up)
- [ ] Native Windows UI

## Contributing

Issues and pull requests are welcome. Please run `cargo fmt` and
`cargo clippy` before submitting.

## License

[MIT](LICENSE)
