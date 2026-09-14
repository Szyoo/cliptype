# CLAUDE.md — cliptype

> 本文件是 [AGENTS.md](AGENTS.md) 的精简镜像，两者保持一致；详细规则以 AGENTS.md 为准。
> 进度与决策记录在 [PROGRESS.md](PROGRESS.md)（最新在上，绝对日期），每次实质进展立刻更新。

## 这是什么

"剪贴板转键盘输入"工具：读剪贴板文本 → 模拟键入，绕过禁止粘贴的输入框。
**最终产品是平台原生常驻应用**（macOS = SwiftUI 应用本体 + 菜单栏；Windows 暂用
Rust tray exe）；Rust CLI 是功能验证 + Linux 形态 + 原生应用同捆的键入引擎。
macOS 为主要开发平台。计划见 [docs/implementation-plan.md](docs/implementation-plan.md)。

## 结构

- [src/main.rs](src/main.rs) — 入口，按参数分派；[src/cli.rs](src/cli.rs) — clap 参数
- [src/clipboard.rs](src/clipboard.rs) — arboard 读剪贴板；[src/typer.rs](src/typer.rs) — enigo 键入 + macOS 权限检测；
  两种发送模式：`unicode`（默认，任意字符/IME 免疫）与 `keycode`（真实键码，VNC/远程控制台/VM 必需）
- [src/keymap.rs](src/keymap.rs) — macOS：键盘布局→键码查表（UCKeyTranslate）+ 发送期间临时切 ASCII 输入源
- [src/hotkey.rs](src/hotkey.rs) — feature `hotkey`：常驻热键（macOS 事件循环必须用
  Carbon `RunApplicationEventLoop`，见 PROGRESS）
- [src/tray.rs](src/tray.rs) — feature `tray`（仅 macOS/Windows）：状态栏 UI
  （tray-icon + tao，菜单状态改动经 EventLoopProxy 回主线程）
- [src/config.rs](src/config.rs) — 托盘设置持久化（std 手写解析，无新依赖）
- [app/macos/](app/macos/) — SwiftUI 菜单栏应用（MenuBarExtra + Settings + Carbon 热键，
  调用同捆 Rust 引擎；键入实现只在 Rust 侧维护）
- [app/macos/.../HistoryPanel.swift](app/macos/Sources/CliptypeApp/HistoryPanel.swift) — 历史面板：非激活
  NSPanel（不抢焦点）、1–9/↑↓/Return 直接键入（`--stdin`）、位置 statusItem 默认 / caret / center / custom
- [app/macos/.../Updater.swift](app/macos/Sources/CliptypeApp/Updater.swift) — 应用内更新（GitHub Releases
  latest → 下载 universal zip → sha256 校验 → bash 助手替换 .app 并重启；资产名后缀与 release.yml 耦合）
- [scripts/bundle-macos.sh](scripts/bundle-macos.sh) — 组装 dist/Cliptype.app；用
  `~/.config/cliptype-signing/` 的自签证书 "Cliptype Signing" 在临时钥匙串里签名
  （DR 稳定 → 更新不丢授权；p12 必须备份、绝不入库；CI 用 Secrets
  `MACOS_SIGNING_P12_BASE64/_PASSWORD`）。详见 AGENTS.md「签名」。

## 关键规则

1. **对话中文；代码注释日语；commit/PR/README/错误提示英文**（开源项目）。
   README 与 CHANGELOG 双语、**中文为默认**（`*.md` 中文 + `*.en.md` 英文，改动同步两份，
   macOS 安装教程分"装应用/终端 CLI"两种方式）；App 界面文案经 `L()` 本地化，
   en/zh-Hans/ja 三语同步（app/macos/.../Resources/*.lproj）。
   Release 正文由 [scripts/release-notes.sh](scripts/release-notes.sh) 从 CHANGELOG 生成，
   不用 GitHub 的 commit 自动生成。
2. **绝不在日志/错误/输出里泄露剪贴板内容**（可能是密码），`--dry-run` 是唯一例外。
   剪贴板历史（[ClipboardHistory.swift](app/macos/Sources/CliptypeApp/ClipboardHistory.swift)）
   默认关闭、只存本机 0600、跳过 concealed 类型；传引擎走 `--stdin` 不走参数。
3. 三平台必须能编译（托盘依赖是 target-specific，Linux 不含）；
   提交前 `cargo fmt` + `cargo clippy --all-features -- -D warnings`。
4. macOS 键入需辅助功能授权，错误提示要引导用户授权。**`AXIsProcessTrusted()` 进程内缓存**，
   App 判权限必须走 `PermissionHelper.isTrustedFresh()`（新进程跑引擎 `--check-permission`）；
   更新后 TCC 旧记录失效需 − / + 重建，UI 必须给出该步骤；辅助功能无一键允许弹窗（系统限制）。
5. 保持小而专，抵制范围蔓延和多余依赖。
