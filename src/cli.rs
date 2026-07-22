//! CLI 引数の定義。
//! `clap` の derive を使ってコマンドライン引数をパースする。

use clap::{Parser, ValueEnum};

// NOTE: 各 doc コメントは --help にそのまま表示されるため英語で書く。

/// `--hotkey` / `--tray` の既定の組み合わせ。
#[cfg(feature = "hotkey")]
pub const DEFAULT_HOTKEY: &str = "ctrl+shift+v";

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

    /// Typing speed preset; a friendlier alternative to --interval
    #[arg(short, long, value_enum, conflicts_with = "interval")]
    pub speed: Option<Speed>,

    /// Print what would be typed instead of typing it
    #[arg(long)]
    pub dry_run: bool,

    /// Stay resident and type the clipboard each time COMBO is pressed
    /// (e.g. "ctrl+shift+v", "alt+F9"); --delay is ignored in this mode
    #[cfg(feature = "hotkey")]
    #[arg(
        long,
        value_name = "COMBO",
        num_args = 0..=1,
        default_missing_value = DEFAULT_HOTKEY
    )]
    pub hotkey: Option<String>,

    /// Like --hotkey, but also shows a status bar / tray icon with settings
    /// (pause, typing speed); combine with --hotkey to change the combo
    #[cfg(all(feature = "tray", any(target_os = "macos", target_os = "windows")))]
    #[arg(long)]
    pub tray: bool,
}

/// 打字速度プリセット。--interval の値へマップされる。
#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum Speed {
    /// No per-key delay (same as --interval 0)
    Fast,
    /// 20 ms per key
    Normal,
    /// 50 ms per key — for apps that drop keys at full speed
    Slow,
}

impl Speed {
    /// プリセットに対応する打鍵間隔（ミリ秒）。トレイの速度メニューと揃えている。
    pub fn interval_ms(self) -> u64 {
        match self {
            Speed::Fast => 0,
            Speed::Normal => 20,
            Speed::Slow => 50,
        }
    }
}

impl Args {
    /// --speed / --interval を解決した実効の打鍵間隔（ミリ秒）。
    pub fn effective_interval_ms(&self) -> u64 {
        self.speed.map(Speed::interval_ms).unwrap_or(self.interval)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn speed_presets_map_to_intervals() {
        assert_eq!(Speed::Fast.interval_ms(), 0);
        assert_eq!(Speed::Normal.interval_ms(), 20);
        assert_eq!(Speed::Slow.interval_ms(), 50);
    }

    #[test]
    fn effective_interval_prefers_speed() {
        let args = Args::parse_from(["cliptype", "--speed", "slow"]);
        assert_eq!(args.effective_interval_ms(), 50);
        let args = Args::parse_from(["cliptype", "--interval", "7"]);
        assert_eq!(args.effective_interval_ms(), 7);
        let args = Args::parse_from(["cliptype"]);
        assert_eq!(args.effective_interval_ms(), 0);
    }

    #[test]
    fn speed_conflicts_with_interval() {
        assert!(Args::try_parse_from(["cliptype", "--speed", "fast", "--interval", "5"]).is_err());
    }
}
