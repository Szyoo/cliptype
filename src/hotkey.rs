//! 常駐ホットキーモード（feature = "hotkey"）。
//! グローバルホットキーを登録し、押されるたびにクリップボードを読み取って送信する。
//!
//! スレッド構成:
//! - メインスレッド: GlobalHotKeyManager の生成・登録と、OS のイベントループ
//!   （macOS は CFRunLoop、Windows は win32 メッセージループが必須。
//!   X11 バックエンドは自前スレッドで処理するため待機のみ）。
//! - ワーカースレッド: イベントチャネルを待ち、押下ごとに読み取り→送信。

use anyhow::{anyhow, Context, Result};
use global_hotkey::{hotkey::HotKey, GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use std::thread;
use std::time::Duration;

use crate::{clipboard, typer};

/// 常駐モードのエントリーポイント。成功時は戻らない（Ctrl+C で終了）。
pub fn run(combo: &str, interval: Duration, dry_run: bool) -> Result<()> {
    // 常駐を始める前に権限を確認して早期に失敗させる
    typer::ensure_permission()?;

    let hotkey: HotKey = combo
        .parse()
        .map_err(|e| anyhow!("invalid hotkey combo {combo:?}: {e}"))?;

    // manager はプロセスが生きている間ずっと保持する必要がある
    let manager = GlobalHotKeyManager::new()
        .map_err(|e| anyhow!("failed to initialize the global hotkey manager: {e}"))?;
    manager
        .register(hotkey)
        .map_err(|e| anyhow!("failed to register hotkey {combo:?} (already in use?): {e}"))?;

    let receiver = GlobalHotKeyEvent::receiver();
    thread::spawn(move || {
        for event in receiver.iter() {
            if event.state != HotKeyState::Pressed {
                continue;
            }
            // 1 回の失敗で常駐を落とさない。エラーにクリップボード内容は含めない。
            if let Err(err) = handle_press(interval, dry_run) {
                eprintln!("error: {err:#}");
            }
        }
    });

    println!("cliptype is resident — press {combo} to type the clipboard (Ctrl+C to quit)");
    run_event_loop();
    Ok(())
}

/// ホットキー押下 1 回分の処理。
fn handle_press(interval: Duration, dry_run: bool) -> Result<()> {
    let text = clipboard::read_text().context("failed to read the clipboard")?;
    if text.is_empty() {
        eprintln!("The clipboard is empty or does not contain text.");
        return Ok(());
    }

    if dry_run {
        println!("--- dry-run ({} chars) ---", text.chars().count());
        println!("{text}");
        return Ok(());
    }

    // ユーザーがまだホットキーの修飾キーを押している間に送信すると
    // 物理修飾キーの状態が合成イベントに混ざるため、離されるまで待つ
    wait_modifiers_released();

    typer::type_text(&text, &typer::TypeOptions { interval })
}

/// macOS: HID システム状態の修飾キーフラグが消えるまで待つ（上限 2 秒）。
#[cfg(target_os = "macos")]
fn wait_modifiers_released() {
    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGEventSourceFlagsState(state_id: u32) -> u64;
    }
    // kCGEventSourceStateHIDSystemState
    const HID_STATE: u32 = 1;
    // shift | control | option | command
    const MODIFIER_MASK: u64 = 0x0002_0000 | 0x0004_0000 | 0x0008_0000 | 0x0010_0000;

    let deadline = std::time::Instant::now() + Duration::from_secs(2);
    while std::time::Instant::now() < deadline {
        if unsafe { CGEventSourceFlagsState(HID_STATE) } & MODIFIER_MASK == 0 {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }
    // 離した直後の取りこぼしを避けるための小さな余裕
    thread::sleep(Duration::from_millis(50));
}

/// macOS 以外: フラグを問い合わせる安価な API が無いため固定で待つ。
#[cfg(not(target_os = "macos"))]
fn wait_modifiers_released() {
    thread::sleep(Duration::from_millis(300));
}

/// macOS: バックエンドはハンドラを GetApplicationEventTarget に登録するため、
/// 素の CFRunLoopRun ではイベントが配送されない。Carbon の
/// RunApplicationEventLoop でアプリケーションイベントループを回す必要がある。
#[cfg(target_os = "macos")]
fn run_event_loop() {
    #[link(name = "Carbon", kind = "framework")]
    extern "C" {
        fn RunApplicationEventLoop();
    }
    unsafe { RunApplicationEventLoop() };
}

/// Windows: WM_HOTKEY を受け取るために win32 メッセージループを回す。
#[cfg(target_os = "windows")]
fn run_event_loop() {
    // MSG 構造体（x64 で 48 バイト）を不透明なバッファとして扱う
    #[repr(C)]
    struct Msg([u64; 6]);

    #[link(name = "user32")]
    extern "system" {
        fn GetMessageW(msg: *mut Msg, hwnd: *mut core::ffi::c_void, min: u32, max: u32) -> i32;
        fn TranslateMessage(msg: *const Msg) -> i32;
        fn DispatchMessageW(msg: *const Msg) -> isize;
    }

    let mut msg = Msg([0; 6]);
    unsafe {
        while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

/// Linux (X11): バックエンドが自前スレッドでイベントを処理するので待つだけ。
#[cfg(not(any(target_os = "macos", target_os = "windows")))]
fn run_event_loop() {
    loop {
        thread::park();
    }
}
