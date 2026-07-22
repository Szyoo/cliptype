//! ステータスバー/トレイ UI（feature = "tray"、macOS / Windows のみ）。
//!
//! tray-icon は各プラットフォームのネイティブ API（macOS: NSStatusItem、
//! Windows: Shell_NotifyIcon）の薄いラッパーなので、見た目は常に OS ネイティブ。
//! メニューの状態変更はメインスレッドでしか行えないため、メニューイベントは
//! tao の EventLoopProxy でメインスレッドのイベントループへ送り返して処理する。
//!
//! スレッド構成:
//! - メインスレッド: tao イベントループ（トレイ生成・メニュー状態の更新）
//! - ワーカースレッド: ホットキー押下を待ち、読み取り→送信（数秒かかるため
//!   メインスレッドを塞がない）

use anyhow::{anyhow, Result};
use global_hotkey::{hotkey::HotKey, GlobalHotKeyEvent, GlobalHotKeyManager, HotKeyState};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tao::event::{Event, StartCause};
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tray_icon::menu::{CheckMenuItem, Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

use crate::{config, hotkey, typer};

/// 速度プリセット（メニュー表示名と interval 値）。
const SPEED_PRESETS: &[(&str, u64)] = &[
    ("Fastest (no per-key delay)", 0),
    ("Steady (20 ms per key)", 20),
    ("Careful (50 ms per key)", 50),
];

/// メニューイベントをメインスレッドへ運ぶためのユーザーイベント。
enum UserEvent {
    Menu(MenuEvent),
}

/// トレイモードのエントリーポイント。成功時は戻らない（Quit メニューで終了）。
pub fn run(combo: &str, cli_interval: Duration, dry_run: bool) -> Result<()> {
    // 常駐を始める前に権限を確認して早期に失敗させる
    typer::ensure_permission()?;

    // interval は「CLI で明示された値 > 保存された設定 > 0」の順で決める。
    // clap のデフォルト（0）と明示指定の 0 は区別できないが、メニューでいつでも
    // Fastest に戻せるため実害はない。
    let initial_interval = if cli_interval.is_zero() {
        config::load().interval_ms
    } else {
        cli_interval.as_millis() as u64
    };

    let paused = Arc::new(AtomicBool::new(false));
    let interval_ms = Arc::new(AtomicU64::new(initial_interval));

    // ホットキー登録。manager はプロセスが生きている間ずっと保持する必要がある
    let hotkey: HotKey = combo
        .parse()
        .map_err(|e| anyhow!("invalid hotkey combo {combo:?}: {e}"))?;
    let manager = GlobalHotKeyManager::new()
        .map_err(|e| anyhow!("failed to initialize the global hotkey manager: {e}"))?;
    manager
        .register(hotkey)
        .map_err(|e| anyhow!("failed to register hotkey {combo:?} (already in use?): {e}"))?;

    // 押下ワーカー
    {
        let paused = paused.clone();
        let interval_ms = interval_ms.clone();
        let receiver = GlobalHotKeyEvent::receiver();
        thread::spawn(move || {
            for event in receiver.iter() {
                if event.state != HotKeyState::Pressed || paused.load(Ordering::Relaxed) {
                    continue;
                }
                let interval = Duration::from_millis(interval_ms.load(Ordering::Relaxed));
                // 1 回の失敗で常駐を落とさない。エラーにクリップボード内容は含めない。
                if let Err(err) = hotkey::handle_press(interval, dry_run) {
                    eprintln!("error: {err:#}");
                }
            }
        });
    }

    // メニュー構築
    let menu = Menu::new();
    let title_item = MenuItem::new(format!("cliptype — {combo}"), false, None);
    let pause_item = CheckMenuItem::new("Pause", true, false, None);
    let speed_menu = Submenu::new("Typing speed", true);
    let speed_items: Vec<CheckMenuItem> = SPEED_PRESETS
        .iter()
        .map(|(label, ms)| CheckMenuItem::new(*label, true, *ms == initial_interval, None))
        .collect();
    // 保存値がプリセット外のときは表示専用の項目として見せる
    let custom_item = (!SPEED_PRESETS.iter().any(|(_, ms)| *ms == initial_interval))
        .then(|| CheckMenuItem::new(format!("Custom ({initial_interval} ms)"), false, true, None));
    for item in &speed_items {
        speed_menu.append(item)?;
    }
    if let Some(custom) = &custom_item {
        speed_menu.append(custom)?;
    }
    let quit_item = MenuItem::new("Quit cliptype", true, None);
    let sep1 = PredefinedMenuItem::separator();
    let sep2 = PredefinedMenuItem::separator();
    menu.append_items(&[
        &title_item,
        &sep1,
        &pause_item,
        &speed_menu,
        &sep2,
        &quit_item,
    ])?;

    // イベントループ。メニューイベントは proxy でメインスレッドへ送り返す
    // （mut は macOS の set_activation_policy にのみ必要）
    #[cfg_attr(not(target_os = "macos"), allow(unused_mut))]
    let mut event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    #[cfg(target_os = "macos")]
    {
        // ステータスバー常駐アプリなので Dock には出さない
        use tao::platform::macos::{ActivationPolicy, EventLoopExtMacOS};
        event_loop.set_activation_policy(ActivationPolicy::Accessory);
    }
    let proxy = event_loop.create_proxy();
    MenuEvent::set_event_handler(Some(move |event: MenuEvent| {
        let _ = proxy.send_event(UserEvent::Menu(event));
    }));

    println!("cliptype is resident in the status bar — press {combo} to type the clipboard");

    let pause_id = pause_item.id().clone();
    let quit_id = quit_item.id().clone();
    let speed_ids: Vec<_> = speed_items.iter().map(|i| i.id().clone()).collect();
    let mut tray: Option<TrayIcon> = None;

    event_loop.run(move |event, _, control_flow| {
        // manager と menu をクロージャに移して生かし続ける
        let _ = (&manager, &menu);
        *control_flow = ControlFlow::Wait;
        match event {
            // トレイアイコンはイベントループ開始後に作る（macOS で必須）
            Event::NewEvents(StartCause::Init) => match build_tray(&menu) {
                Ok(t) => tray = Some(t),
                Err(err) => {
                    eprintln!("error: failed to create the tray icon: {err:#}");
                    *control_flow = ControlFlow::Exit;
                }
            },
            Event::UserEvent(UserEvent::Menu(menu_event)) => {
                let id = menu_event.id();
                if *id == quit_id {
                    *control_flow = ControlFlow::Exit;
                } else if *id == pause_id {
                    // CheckMenuItem はクリックで自動トグルされるので状態を読むだけ
                    paused.store(pause_item.is_checked(), Ordering::Relaxed);
                } else if let Some(idx) = speed_ids.iter().position(|s| s == id) {
                    let ms = SPEED_PRESETS[idx].1;
                    interval_ms.store(ms, Ordering::Relaxed);
                    for (i, item) in speed_items.iter().enumerate() {
                        item.set_checked(i == idx);
                    }
                    if let Some(custom) = &custom_item {
                        custom.set_checked(false);
                    }
                    // 保存失敗で常駐は止めない（次回起動に引き継がれないだけ）
                    if let Err(err) = config::save(&config::Config { interval_ms: ms }) {
                        eprintln!("warning: failed to save settings: {err}");
                    }
                }
            }
            _ => {}
        }
        // 未使用警告避け: tray はドロップさせないために保持している
        let _ = &tray;
    });
}

/// トレイアイコンを生成する。
fn build_tray(menu: &Menu) -> Result<TrayIcon> {
    TrayIconBuilder::new()
        .with_menu(Box::new(menu.clone()))
        .with_icon(build_icon())
        // macOS: テンプレート画像としてライト/ダークに自動追従（他 OS では無視）
        .with_icon_as_template(true)
        .with_tooltip("cliptype")
        .build()
        .map_err(|e| anyhow!("{e}"))
}

/// 32x32 のキーボード風グリフをコードで描く（外部アセット不要）。
fn build_icon() -> Icon {
    const W: usize = 32;
    const H: usize = 32;
    // macOS はテンプレート画像（形はアルファで決まる）なので黒、
    // Windows は暗いタスクバーでも見えるように明るい色にする
    #[cfg(target_os = "macos")]
    const COLOR: [u8; 3] = [0, 0, 0];
    #[cfg(not(target_os = "macos"))]
    const COLOR: [u8; 3] = [230, 230, 230];

    let mut rgba = vec![0u8; W * H * 4];
    let mut fill = |x0: usize, y0: usize, x1: usize, y1: usize| {
        for y in y0..y1 {
            for x in x0..x1 {
                let i = (y * W + x) * 4;
                rgba[i..i + 3].copy_from_slice(&COLOR);
                rgba[i + 3] = 255;
            }
        }
    };

    // キーボードの外枠（線幅 2）
    fill(2, 7, 30, 9); // 上辺
    fill(2, 23, 30, 25); // 下辺
    fill(2, 7, 4, 25); // 左辺
    fill(28, 7, 30, 25); // 右辺
                         // キーのドット 2 段
    for row in 0..2 {
        let y = 11 + row * 4;
        for col in 0..6 {
            let x = 6 + col * 4;
            fill(x, y, x + 2, y + 2);
        }
    }
    // スペースバー
    fill(9, 19, 23, 21);

    Icon::from_rgba(rgba, W as u32, H as u32).expect("icon buffer has the right size")
}
