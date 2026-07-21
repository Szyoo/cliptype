//! CLI 引数の定義。
//! `clap` の derive を使ってコマンドライン引数をパースする。

use clap::Parser;

// NOTE: 各 doc コメントは --help にそのまま表示されるため英語で書く。

/// Type the contents of your clipboard as simulated keystrokes.
#[derive(Parser, Debug)]
#[command(name = "cliptype", version, about)]
pub struct Args {
    /// Delay before typing starts, in ms (time to focus the target window)
    #[arg(short, long, default_value_t = 2000)]
    pub delay: u64,

    /// Delay between keystrokes, in ms (0 = fastest)
    #[arg(short, long, default_value_t = 0)]
    pub interval: u64,

    /// Print what would be typed instead of typing it
    #[arg(long)]
    pub dry_run: bool,
    // TODO: --hotkey フラグ（常駐モード）を hotkey フィーチャー有効時に追加する。
}
