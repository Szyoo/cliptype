//! キーストローク送信モジュール。
//! `enigo` を使って、与えられたテキストを実際のキー入力として送信する。

use anyhow::Result;
use std::time::Duration;

/// 送信時の挙動を制御する設定。
pub struct TypeOptions {
    /// 各文字の入力間隔。
    // TODO: type_text 実装時にこの allow を外す（現状 stub のため未読）。
    #[allow(dead_code)]
    pub interval: Duration,
}

/// `text` をキーストロークとして送信する。
///
/// TODO: 実装する。
/// - `enigo::Enigo::new(&Settings::default())?` を生成
/// - `enigo.text(&text)?` で文字列を入力、
///   もしくは interval を挟みながら 1 文字ずつ送信
/// - 改行・タブ・Unicode（日本語/絵文字）の扱いを検証
pub fn type_text(_text: &str, _opts: &TypeOptions) -> Result<()> {
    anyhow::bail!("type_text は未実装です");
}
