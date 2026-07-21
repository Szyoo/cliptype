//! CLI 引数の定義。
//! `clap` の derive を使ってコマンドライン引数をパースする。

use clap::Parser;

/// クリップボードの中身をキーストロークとして送信するツール。
#[derive(Parser, Debug)]
#[command(name = "cliptype", version, about)]
pub struct Args {
    /// 入力を開始するまでの遅延（ミリ秒）。ウィンドウ切り替えの猶予に使う。
    #[arg(short, long, default_value_t = 2000)]
    pub delay: u64,

    /// 各キーストローク間の間隔（ミリ秒）。0 で最速。
    #[arg(short, long, default_value_t = 0)]
    pub interval: u64,

    /// 送信せずに、送る予定の内容を表示するだけ（ドライラン）。
    #[arg(long)]
    pub dry_run: bool,
    // TODO: --hotkey フラグ（常駐モード）を hotkey フィーチャー有効時に追加する。
}
