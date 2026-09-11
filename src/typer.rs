//! キーストローク送信モジュール。
//! `enigo` を使って、与えられたテキストを実際のキー入力として送信する。

use anyhow::{anyhow, Result};
use enigo::{Direction::Click, Enigo, Key, Keyboard, Settings};
use std::thread;
use std::time::Duration;

/// キーストロークの送り方。
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum InputMode {
    /// Unicode 文字列を添付したイベント。任意の文字を打てて IME にも横取り
    /// されないが、キーコードが 0 固定なので VNC 等では全文字 "a" になる。
    #[default]
    Unicode,
    /// 現在のキーボード配列で実キーコード + 修飾キーを押す。VNC / リモート
    /// コンソール / VM 向け。配列に無い文字（CJK 等）は Unicode 方式へ退避。
    Keycode,
}

/// 送信時の挙動を制御する設定。
pub struct TypeOptions {
    /// 各文字の入力間隔。
    pub interval: Duration,
    /// 送信方式。
    pub mode: InputMode,
}

/// `text` をキーストロークとして送信する。
///
/// 改行コードは送信前に LF へ統一する（Windows 由来の CRLF が
/// 二重改行になるのを防ぐ）。改行・タブは `text()` に混ぜると
/// アプリによっては Return/Tab として解釈されないため、
/// 専用キーとして送信する。
pub fn type_text(text: &str, opts: &TypeOptions) -> Result<()> {
    ensure_permission()?;
    let text = normalize_newlines(text);
    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| {
        anyhow!(
            "failed to initialize keyboard simulation: {e}{}",
            permission_hint()
        )
    })?;

    let result = match opts.mode {
        InputMode::Unicode if opts.interval.is_zero() => type_fast(&mut enigo, &text),
        InputMode::Unicode => type_per_char(&mut enigo, &text, opts.interval),
        InputMode::Keycode => type_keycodes(&mut enigo, &text, opts.interval),
    };

    // 送信直後にプロセスが終了すると、未配送のイベントが失われて
    // 末尾の文字が欠けることがある（実測で確認）。少し待ってから戻る。
    thread::sleep(Duration::from_millis(120));
    result
}

/// 最速モード: 通常文字はまとめて `text()` で送り、改行・タブだけキー送信する。
fn type_fast(enigo: &mut Enigo, text: &str) -> Result<()> {
    let mut buf = String::new();
    for ch in text.chars() {
        match ch {
            '\n' | '\t' => {
                flush(enigo, &mut buf)?;
                send_special(enigo, ch)?;
            }
            _ => buf.push(ch),
        }
    }
    flush(enigo, &mut buf)
}

/// 逐字モード: 1 文字ずつ送信し、間に interval を挟む。
/// `Key::Unicode` は物理キーコードの模倣になるため IME に横取りされる
/// （実測: 中国語 IME 有効時に「日本語」→「啊啊啊」）。`text()` と同じ
/// unicode 文字列添付方式なら IME を素通りするので、1 文字ずつ `text()` で送る。
fn type_per_char(enigo: &mut Enigo, text: &str, interval: Duration) -> Result<()> {
    let mut buf = [0u8; 4];
    for ch in text.chars() {
        match ch {
            '\n' | '\t' => send_special(enigo, ch)?,
            _ => enigo.text(ch.encode_utf8(&mut buf)).map_err(input_err)?,
        }
        thread::sleep(interval);
    }
    Ok(())
}

/// 実キーコードモード（macOS）: 現在の配列で文字ごとにキーコード + 修飾キーを
/// 引いて実キー押下として送る。VNC / リモートコンソールは添付 Unicode を無視して
/// キーコードだけを転送するため、このモードでないと全文字が "a" になる。
/// 送信中は IME を避けて ASCII 配列へ一時切替する（終了時に復元）。
#[cfg(target_os = "macos")]
fn type_keycodes(enigo: &mut Enigo, text: &str, interval: Duration) -> Result<()> {
    use crate::keymap::{AsciiInputSourceGuard, LayoutMap};
    use enigo::Direction::{Press, Release};

    let layout = LayoutMap::current()?;
    let _ascii = AsciiInputSourceGuard::activate();
    let mut warned = false;
    let mut buf = [0u8; 4];

    for ch in text.chars() {
        match ch {
            '\n' | '\t' => send_special(enigo, ch)?,
            _ => match layout.lookup(ch) {
                Some(stroke) => {
                    if stroke.shift {
                        enigo.key(Key::Shift, Press).map_err(input_err)?;
                    }
                    if stroke.option {
                        enigo.key(Key::Alt, Press).map_err(input_err)?;
                    }
                    let sent = enigo.raw(stroke.keycode, Click).map_err(input_err);
                    // エラーでも修飾キーは必ず離す（押しっぱなし事故を防ぐ）
                    if stroke.option {
                        enigo.key(Key::Alt, Release).map_err(input_err)?;
                    }
                    if stroke.shift {
                        enigo.key(Key::Shift, Release).map_err(input_err)?;
                    }
                    sent?;
                }
                None => {
                    if !warned {
                        eprintln!(
                            "warning: some characters are not on the current keyboard layout \
                             and were sent as unicode text; remote consoles may not receive them"
                        );
                        warned = true;
                    }
                    enigo.text(ch.encode_utf8(&mut buf)).map_err(input_err)?;
                }
            },
        }
        thread::sleep(interval);
    }
    Ok(())
}

/// 実キーコードモード（macOS 以外）: enigo の `Key::Unicode` に任せる
/// （Windows は VkKeyScan で配列に応じたキーコード + Shift を解決する）。
#[cfg(not(target_os = "macos"))]
fn type_keycodes(enigo: &mut Enigo, text: &str, interval: Duration) -> Result<()> {
    for ch in text.chars() {
        match ch {
            '\n' | '\t' => send_special(enigo, ch)?,
            _ => enigo.key(Key::Unicode(ch), Click).map_err(input_err)?,
        }
        thread::sleep(interval);
    }
    Ok(())
}

/// バッファに溜めた通常文字を一括送信してクリアする。
fn flush(enigo: &mut Enigo, buf: &mut String) -> Result<()> {
    if !buf.is_empty() {
        enigo.text(buf).map_err(input_err)?;
        buf.clear();
    }
    Ok(())
}

/// 改行・タブを専用キーとして送信する。
fn send_special(enigo: &mut Enigo, ch: char) -> Result<()> {
    let key = match ch {
        '\n' => Key::Return,
        '\t' => Key::Tab,
        _ => unreachable!("send_special は改行・タブ以外を受け取らない"),
    };
    enigo.key(key, Click).map_err(input_err)
}

/// 送信エラーを整形する。クリップボード内容は絶対に含めない。
fn input_err(e: enigo::InputError) -> anyhow::Error {
    anyhow!("failed to send keystrokes: {e}{}", permission_hint())
}

/// macOS: アクセシビリティ権限が無いと CGEvent は OS に静かに破棄され、
/// enigo もエラーを返さない（0.2.1 は権限チェックを行わない）。
/// 「何も入力されないのに正常終了する」を防ぐため、送信前に明示的に確認する。
#[cfg(target_os = "macos")]
pub fn ensure_permission() -> Result<()> {
    #[link(name = "ApplicationServices", kind = "framework")]
    extern "C" {
        fn AXIsProcessTrusted() -> bool;
    }
    if unsafe { AXIsProcessTrusted() } {
        Ok(())
    } else {
        anyhow::bail!(
            "the Accessibility permission is not granted, so macOS would silently \
             discard the keystrokes.{}",
            permission_hint()
        )
    }
}

/// macOS 以外では権限チェック不要。
#[cfg(not(target_os = "macos"))]
pub fn ensure_permission() -> Result<()> {
    Ok(())
}

/// macOS の場合のみ、アクセシビリティ権限の案内を付ける。
fn permission_hint() -> &'static str {
    if cfg!(target_os = "macos") {
        "\nhint: open System Settings → Privacy & Security → Accessibility, add the \
         terminal app you run cliptype from (e.g. Terminal / iTerm) and enable it, \
         then fully quit and reopen that terminal app and retry"
    } else {
        ""
    }
}

/// 改行コードを LF に統一する（CRLF → LF、単独 CR → LF）。
fn normalize_newlines(text: &str) -> String {
    text.replace("\r\n", "\n").replace('\r', "\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crlf_becomes_lf() {
        assert_eq!(normalize_newlines("a\r\nb"), "a\nb");
    }

    #[test]
    fn lone_cr_becomes_lf() {
        assert_eq!(normalize_newlines("a\rb"), "a\nb");
    }

    #[test]
    fn mixed_line_endings() {
        assert_eq!(normalize_newlines("a\r\nb\rc\nd"), "a\nb\nc\nd");
    }

    #[test]
    fn unicode_and_tab_untouched() {
        assert_eq!(normalize_newlines("日本語🌏\tタブ"), "日本語🌏\tタブ");
    }

    #[test]
    fn empty_string() {
        assert_eq!(normalize_newlines(""), "");
    }
}
