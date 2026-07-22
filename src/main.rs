//! cliptype エントリーポイント。
//! クリップボードの内容を読み取り、キーストロークとして送信する。

mod cli;
mod clipboard;
mod typer;

use anyhow::Result;
use clap::Parser;
use std::thread;
use std::time::Duration;

fn main() -> Result<()> {
    let args = cli::Args::parse();

    // クリップボードからテキストを取得
    let text = clipboard::read_text()?;
    if text.is_empty() {
        eprintln!("The clipboard is empty or does not contain text.");
        return Ok(());
    }

    // ドライラン: 送信せず内容を表示するだけ
    if args.dry_run {
        println!("--- dry-run ({} chars) ---", text.chars().count());
        println!("{text}");
        return Ok(());
    }

    // 権限が無いならカウントダウンで待たせる前に失敗させる
    typer::ensure_permission()?;

    // ウィンドウを切り替える猶予を与える
    println!(
        "Typing starts in {}ms — focus the target window now…",
        args.delay
    );
    thread::sleep(Duration::from_millis(args.delay));

    // キーストローク送信
    let opts = typer::TypeOptions {
        interval: Duration::from_millis(args.interval),
    };
    typer::type_text(&text, &opts)?;

    Ok(())
}
