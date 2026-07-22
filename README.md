# cliptype

Type the contents of your clipboard as simulated keystrokes.

`cliptype` reads whatever text is on your clipboard and "types" it out character
by character as real keyboard input. This is useful for fields that block
paste — remote desktop sessions, VMs, some password prompts, kiosk software, and
similar environments where <kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> simply doesn't work.

Cross-platform: **macOS**, **Windows**, and **Linux**.

> Status: core functionality and the optional resident hotkey mode are
> implemented and verified on macOS. Windows/Linux runtime verification is
> in progress. See the [Roadmap](#roadmap).

## How it works

1. Read the current clipboard text (via [`arboard`](https://crates.io/crates/arboard)).
2. Wait a short, configurable delay so you can focus the target window.
3. Send the text as keystrokes (via [`enigo`](https://crates.io/crates/enigo)).

## Usage

```
cliptype [OPTIONS]

Options:
  -d, --delay <MS>      Delay before typing starts, in ms  [default: 2000]
  -i, --interval <MS>   Delay between keystrokes, in ms     [default: 0]
      --dry-run         Print what would be typed instead of typing it
  -h, --help            Print help
  -V, --version         Print version
```

Example:

```sh
# Copy some text, then:
cliptype --delay 3000
# Switch to the target window within 3s; the clipboard text is typed in.
```

### Resident hotkey mode (optional)

When built with the `hotkey` feature, `cliptype --hotkey` stays resident and
types the current clipboard every time you press the hotkey — no countdown, no
window switching; just focus the target field and press the combo:

```sh
cargo build --release --features hotkey

cliptype --hotkey                    # default combo: ctrl+shift+v
cliptype --hotkey "alt+F9"           # custom combo
cliptype --hotkey --interval 20      # per-character typing on each press
```

`cliptype` waits until the hotkey's modifier keys are released before typing,
so the combo itself does not contaminate the output. `--delay` is ignored in
this mode. Press <kbd>Ctrl</kbd>+<kbd>C</kbd> in the terminal to quit.

## Platform notes

### macOS
Simulating keystrokes requires the **Accessibility** permission. Grant it under
*System Settings → Privacy & Security → Accessibility*, and add the terminal app
you run `cliptype` from to the allowed list. After granting, **fully quit and
reopen the terminal app** — the permission is not picked up by already-running
processes.

Without the permission, macOS silently discards simulated keystrokes; `cliptype`
detects this and exits with an error instead of appearing to succeed while
typing nothing.

### Linux
On X11, `enigo`/`arboard` depend on `libxdo` and X11 development libraries.
On Debian/Ubuntu:

```sh
sudo apt-get install -y libxdo-dev libxcb1-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev
```

Wayland support depends on your compositor; XWayland generally works.

### Windows
No extra setup required.

## Build from source

Requires a [Rust toolchain](https://rustup.rs/).

```sh
git clone https://github.com/Szyoo/cliptype
cd cliptype
cargo build --release
# binary at ./target/release/cliptype
```

## Roadmap

- [x] Implement clipboard text read (`clipboard::read_text`)
- [x] Implement keystroke sending (`typer::type_text`)
- [ ] Verify Unicode / newline / tab handling across platforms
- [x] Optional resident hotkey mode (`--features hotkey`)
- [ ] Prebuilt release binaries for macOS / Windows / Linux
- [ ] Configurable "typing speed" presets

## Contributing

Issues and pull requests are welcome. Please run `cargo fmt` and
`cargo clippy` before submitting.

## License

[MIT](LICENSE)
