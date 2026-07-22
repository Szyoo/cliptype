//! 設定の永続化（トレイ UI 用）。
//! 依存を増やさないため、1 行 1 設定の `key = value` 形式を自前で読み書きする。
//! 場所: `~/.config/cliptype/config.toml`（Windows は `%APPDATA%\cliptype\`）。

use std::fs;
use std::path::PathBuf;

/// 保存対象の設定。今は打鍵間隔のみ。
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Config {
    /// 各キーストローク間の間隔（ミリ秒）。0 = 最速。
    pub interval_ms: u64,
}

/// 設定ファイルを読む。無い・壊れている場合はデフォルトに黙って戻る
/// （UI 起動を設定ファイルの事情で失敗させない）。
pub fn load() -> Config {
    config_path()
        .and_then(|p| fs::read_to_string(p).ok())
        .map(|s| parse(&s))
        .unwrap_or_default()
}

/// 設定ファイルへ書き出す。
pub fn save(config: &Config) -> std::io::Result<()> {
    let Some(path) = config_path() else {
        return Ok(()); // 保存先が決められない環境では何もしない
    };
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir)?;
    }
    fs::write(
        path,
        format!(
            "# cliptype settings — written by the tray UI\ninterval_ms = {}\n",
            config.interval_ms
        ),
    )
}

/// 設定ファイルの置き場所。
fn config_path() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    let base = std::env::var_os("APPDATA").map(PathBuf::from)?;
    #[cfg(not(target_os = "windows"))]
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("cliptype").join("config.toml"))
}

/// `key = value` 形式をパースする。未知のキー・壊れた行は無視。
fn parse(s: &str) -> Config {
    let mut config = Config::default();
    for line in s.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some((key, value)) = line.split_once('=') {
            if key.trim() == "interval_ms" {
                if let Ok(n) = value.trim().parse() {
                    config.interval_ms = n;
                }
            }
        }
    }
    config
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_reads_interval() {
        let c = parse("# comment\ninterval_ms = 20\n");
        assert_eq!(c.interval_ms, 20);
    }

    #[test]
    fn parse_ignores_junk_and_unknown_keys() {
        let c = parse("garbage line\nfoo = bar\ninterval_ms = oops\n");
        assert_eq!(c, Config::default());
    }

    #[test]
    fn parse_empty_is_default() {
        assert_eq!(parse(""), Config::default());
    }
}
