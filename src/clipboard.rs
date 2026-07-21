//! クリップボード読み取りモジュール。
//! `arboard` を使って OS のクリップボードからテキストを取得する。

use anyhow::Result;

/// クリップボードのテキストを取得する。
///
/// TODO: 実装する。
/// - `arboard::Clipboard::new()?` でハンドルを取得
/// - `.get_text()` でテキストを読み取る
/// - 空・非テキスト（画像等）の場合のハンドリング
pub fn read_text() -> Result<String> {
    anyhow::bail!("read_text は未実装です");
}
