//! キーストローク送信モジュール。
//! `enigo` を使って、与えられたテキストを実際のキー入力として送信する。

use anyhow::{anyhow, Result};
use enigo::{Direction::Click, Enigo, Key, Keyboard, Settings};
use std::thread;
use std::time::Duration;

/// 送信時の挙動を制御する設定。
pub struct TypeOptions {
    /// 各文字の入力間隔。
    pub interval: Duration,
}

/// `text` をキーストロークとして送信する。
///
/// 改行コードは送信前に LF へ統一する（Windows 由来の CRLF が
/// 二重改行になるのを防ぐ）。改行・タブは `text()` に混ぜると
/// アプリによっては Return/Tab として解釈されないため、
/// 専用キーとして送信する。
pub fn type_text(text: &str, opts: &TypeOptions) -> Result<()> {
    let text = normalize_newlines(text);
    let mut enigo = Enigo::new(&Settings::default()).map_err(|e| {
        anyhow!(
            "failed to initialize keyboard simulation: {e}{}",
            permission_hint()
        )
    })?;

    if opts.interval.is_zero() {
        type_fast(&mut enigo, &text)
    } else {
        type_per_char(&mut enigo, &text, opts.interval)
    }
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
fn type_per_char(enigo: &mut Enigo, text: &str, interval: Duration) -> Result<()> {
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

/// macOS の場合のみ、アクセシビリティ権限の案内を付ける。
fn permission_hint() -> &'static str {
    if cfg!(target_os = "macos") {
        "\nhint: grant Accessibility permission to your terminal app under \
         System Settings → Privacy & Security → Accessibility, then retry"
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
