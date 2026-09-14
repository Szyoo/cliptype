# AGENTS.md — cliptype 项目说明

本文件是 agent 在本仓库工作时的权威指引，开工前先读一遍。
**CLAUDE.md 是本文件的精简镜像；两者保持一致。**

## ⚠️ 第一要求：随时更新进度

**每次有实质进展、决策、或卡点时，必须更新 [PROGRESS.md](PROGRESS.md)（最新放最上）。**
- 完成一个模块、做出一个技术决策、遇到阻塞 → 立刻记进 PROGRESS.md，不要等会话结束才补记。
- 重大决策同时更新本文件和 CLAUDE.md 的相关部分。
- 日期一律写绝对日期（如 2026-07-21），不要写"今天/昨天"。

## 项目速览

跨平台"剪贴板转键盘输入"工具：读取剪贴板文本，模拟键入，用于禁止粘贴的输入框
（远程桌面、VM、部分密码框等）。思路借鉴一个 Windows-only 的 AutoHotkey 小工具，
但是**全新实现，不含任何原始代码**。

**产品形态（2026-07-22 用户确定）**：最终产品是平台原生常驻应用；Rust CLI 是
功能验证手段 + Linux 形态 + 各原生应用同捆的键入引擎。macOS = SwiftUI 应用
（应用本体/设置窗口 + 常驻菜单栏）；Windows = 暂用 Rust tray exe，将来原生化；
两平台界面独立维护、打包互不包含对方内容。

- [src/main.rs](src/main.rs) — 入口：按参数分派到单次/热键/托盘模式。
- [src/cli.rs](src/cli.rs) — clap derive 参数：`--delay` / `--interval` / `--dry-run` /
  `--hotkey [COMBO]`（feature hotkey）/ `--tray`（feature tray）。
- [src/clipboard.rs](src/clipboard.rs) — `read_text()`，用 `arboard`。
- [src/typer.rs](src/typer.rs) — `type_text()`（enigo）+ macOS 辅助功能权限检测。
  两种发送模式：`InputMode::Unicode`（默认；Unicode 文本事件，任意字符、IME 免疫，
  但键码固定 0）与 `InputMode::Keycode`（真实键码 + Shift/Option；VNC / 远程控制台 /
  VM 只转发键码，不开此模式全变 "a"）。
- [src/keymap.rs](src/keymap.rs) — macOS 专用：用 `UCKeyTranslate` 按当前键盘布局
  建"字符→键码+修饰键"表；`AsciiInputSourceGuard` 发送期间临时切到 ASCII 输入源
  避开 IME，结束恢复。全部 Carbon FFI，无新依赖。
- [src/hotkey.rs](src/hotkey.rs) — feature `hotkey`：常驻热键模式（global-hotkey）。
  macOS 事件循环必须用 Carbon `RunApplicationEventLoop`（见 PROGRESS 2026-07-22）。
- [src/tray.rs](src/tray.rs) — feature `tray`（仅 macOS/Windows）：状态栏/托盘 UI
  （tray-icon + tao），菜单改设置须在主线程（经 EventLoopProxy 转发）。
- [src/config.rs](src/config.rs) — 托盘设置持久化（std 手写 key=value，无新依赖）。
- 依赖用 target-specific dependencies 隔离：macOS 二进制不含 Windows UI 代码，
  反之亦然；Linux 构建完全不引入托盘依赖（GTK 太重，托盘不支持 Linux）。
- [app/macos/](app/macos/) — SwiftUI 菜单栏应用（SwiftPM，macOS 14+）：MenuBarExtra +
  Settings 窗口 + Carbon 热键；按热键时调用同捆的 Rust 引擎（`--delay 0` 单次模式）。
  键入实现只在 Rust 侧维护，Swift 不重复实现。
- [app/macos/.../Updater.swift](app/macos/Sources/CliptypeApp/Updater.swift) — 应用内更新：
  查 GitHub Releases latest → 下载 `*-macos-app-universal.zip` → 对照同一 Release 的
  `.sha256` 校验 → ditto 解压 → 独立 bash 助手等主进程退出后替换 .app、清 quarantine、
  `tccutil reset` 我们的 bundle id、`open` 重启。资产文件名后缀与 release.yml 耦合，
  改名要两边同步。不用 Sparkle（签名密钥 + appcast 运维过重）。
- [app/macos/.../ClipboardHistory.swift](app/macos/Sources/CliptypeApp/ClipboardHistory.swift) — 剪贴板
  历史基础层（模型 + 0.5s changeCount 轮询 + JSON 持久化 + 操作 API）。**默认关闭**；
  跳过 concealed/transient 类型；保存于 `~/Library/Application Support/Cliptype/history.json`
  （0700/0600）。UI 形态待定，当前只有菜单子菜单占位。直接键入走引擎 `--stdin`。
- [app/macos/.../HistoryPanel.swift](app/macos/Sources/CliptypeApp/HistoryPanel.swift) +
  [HistoryPanelView.swift](app/macos/Sources/CliptypeApp/HistoryPanelView.swift) — 历史面板：
  **非激活 NSPanel**（绝不 `NSApp.activate`，否则目标输入框失焦、字打进面板）；键盘由
  `NSEvent` 本地监视器先处理（Esc/Return/↑↓/1–9），其余流给搜索框；选中后先 `orderOut`
  再延迟 120ms 走引擎 `--stdin`。定位 `PanelPosition`（statusItem 默认 / caret / center /
  custom）；状态栏图标位置来自进程内 `NSStatusBarWindow`。面板热键 = HotkeyManager id 2。
  显示条数 `panelMaxItems`（3–9）决定数字快捷键范围与面板高度。
- [app/macos/.../KeyCombo.swift](app/macos/Sources/CliptypeApp/KeyCombo.swift) +
  [HotkeyRecorderView.swift](app/macos/Sources/CliptypeApp/HotkeyRecorderView.swift) — 热键**自由录制**
  （用户反馈预设与其他软件冲突）。`KeyCombo` = Carbon keyCode + 修饰键，存 UserDefaults
  `hotkeyCombo` / `panelHotkeyCombo`（"keyCode:mods"），旧 `*PresetId` 自动迁移；标签用
  UCKeyTranslate 按当前配列取键名。录制期间 `suspendHotkeys` 解除全局热键（Carbon 会先截走
  事件）；注册失败（被占用）通过 `hotkeyError` 显示。
- [scripts/bundle-macos.sh](scripts/bundle-macos.sh) — 组装 dist/Cliptype.app
  （LSUIElement、ad-hoc 签名；TCC 只需授权 App 一处，子进程引擎自动继承）。

实施计划见 [docs/implementation-plan.md](docs/implementation-plan.md)，当前进度见 [PROGRESS.md](PROGRESS.md)。

## 语言规范

- **对话**：与用户交流一律使用中文。
- **代码注释**：日语（用户个人偏好，遵循既有代码风格）；标识符、变量名用英文。
- **git / 面向公众的文本**：这是开源项目——commit message、PR、README、错误提示等
  用户可见输出一律用英文。
- **README 双语（中文为默认）**：README.md（中文，仓库默认展示）+ README.en.md
  （英文镜像），顶部互链；改 README 内容必须同步两份。安装章节必须区分
  macOS 的两种方式（装应用 / 终端 CLI）并各配教程。
- **CHANGELOG 同样双语**：CHANGELOG.md（中文）+ CHANGELOG.en.md（英文），两份同步。
  条目写"用户看得懂的变化"，不是 commit 摘要。GitHub Release 正文由
  [scripts/release-notes.sh](scripts/release-notes.sh) 从两份 CHANGELOG 抽取该版本
  小节生成（中英并列），**不要**用 `generate_release_notes`（那只会罗列 commit）。
  这段正文也会原样显示在应用内更新弹窗里。
- **App 界面多语言**：SwiftUI 文案一律经 `L()` 助手（[app/macos/.../L10n.swift](app/macos/Sources/CliptypeApp/L10n.swift)），
  键 = 英文原文；翻译在 `Resources/{en,zh-Hans,ja}.lproj/Localizable.strings`，
  新增 UI 文案必须三语同步。

## 核心设计原则

1. **绝不泄露剪贴板内容**：剪贴板里可能是密码。除显式的 `--dry-run` 外，
   任何日志、错误信息、panic 输出都不得包含剪贴板文本（长度、字符数可以）。
   剪贴板历史是唯一把内容落盘的功能：必须默认关闭、只存本机 Application Support
   （0600）、跳过密码管理器的 concealed/transient 类型、随时可清空；向引擎传历史
   条目一律走 stdin，不走命令行参数（`ps` 可见）。
2. **默认安全**：键入前必须有可感知的延迟（默认 2000ms）并提示用户切换窗口；
   不做任何"自动聚焦目标窗口"的魔法。
3. **跨平台一致**：新功能必须三平台都能编译（CI 会验证）；平台差异集中在模块内部处理，
   不泄漏到 main.rs。
4. **保持小而专**：这是单一用途 CLI，抵制范围蔓延；新依赖要有充分理由。

## 平台注意事项

- **macOS**（主要开发/验证平台）：模拟键入需要「系统设置 → 隐私与安全性 → 辅助功能」授权；
  未授权时 enigo 会静默失败或报错，错误提示里要引导用户去授权。
  - **`AXIsProcessTrusted()` 在进程内被缓存**：运行中的进程看不到授权/撤销的变化
    （实测两个方向都如此）。App 里判断权限一律走 `PermissionHelper.isTrustedFresh()`
    ——起一个新进程跑引擎的 `--check-permission`，不要在 UI 里直接轮询 AX API。
  - **TCC 记录绑定签名指纹**：ad-hoc 签名每次构建都变，更新替换 .app 后旧记录失效，
    开关关开无效，必须 − 删除再 + 添加（客户报告确认）。`tccutil reset <bundle-id>`
    对路径键控的记录可能无效，所以 UI 必须同时给出手动 − / + 步骤。
  - 辅助功能属于高危权限，系统不提供一键「允许」弹窗，只能引导到系统设置——这是
    Apple 的限制，不可自定义，不要再花时间找绕过办法。
- **Linux (X11)**：需要 `libxdo-dev` 和 xcb 系列开发库（CI 已安装）；Wayland 支持有限，
  依赖 compositor，README 已说明。
- **Windows**：无需额外配置。

## 签名（macOS 应用）

- **为什么**：TCC 把辅助功能授权绑定在应用的签名要求（DR）上。ad-hoc 签名的 DR 是
  内容哈希、每次构建都变 → 每次更新用户都要重新授权（客户投诉的根因）。证书签名的
  DR 是 `identifier "io.github.szyoo.cliptype" and certificate root = H"<证书哈希>"`，
  跨构建不变 → 授权永久有效（已实测：两个不同二进制 DR 完全相同）。
- **证书**：自签代码签名证书 "Cliptype Signing"（RSA 2048，10 年，codeSigning EKU）。
  本机存放 `~/.config/cliptype-signing/`（0700）：`cliptype-signing.p12`、
  `p12-password.txt`、`cert.pem`、`key.pem`（均 0600）。**必须备份 p12 + 密码**——
  丢失 = 只能换新证书 = 所有用户再重新授权一次。**绝不提交进仓库。**
- **CI**：GitHub Secrets `MACOS_SIGNING_P12_BASE64`（p12 的 base64）与
  `MACOS_SIGNING_P12_PASSWORD`。release.yml 把 p12 写到 `$RUNNER_TEMP` 并设
  `CODESIGN_P12`，其余交给脚本；Secrets 缺失（fork）时自动退回 ad-hoc。
- **脚本**：[scripts/bundle-macos.sh](scripts/bundle-macos.sh) 自动发现 p12
  （或 `CODESIGN_P12` / `CODESIGN_P12_PASSWORD` 环境变量），在**一次性临时钥匙串**里
  导入并签名（`--timestamp=none`，自签无 TSA），结束删除。不碰登录钥匙串 → 不弹
  「codesign 想访问密钥」对话框。codesign 本身**不需要**系统信任这张证书。
- **注意**：p12 必须用旧式算法导出（`-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
  -macalg sha1`），OpenSSL 3 默认的 AES/PBKDF2 导出 macOS `security import` 会报
  "MAC verification failed"。
- **更新助手不得再 `tccutil reset`**（会丢掉有效授权）。从 ≤0.1.2 升级的一次性失效
  由 12 秒后的引导弹窗处理。
- **升级到 Apple Developer ID**：只需替换 p12（Developer ID Application 证书）、
  去掉 `--timestamp=none`、加 notarytool 公证步骤；DR 换成 Team ID 形式，用户再重新
  授权一次即可，之后 Gatekeeper 提示也消失。

## 工程流程

- **会话内**：非平凡的多步任务用 TaskCreate/TaskUpdate 跟踪，完成即时标记。
- 提交前跑 `cargo fmt` 和 `cargo clippy -- -D warnings`（CI 同样标准）。
- 文本处理逻辑（换行归一化等）抽成纯函数写单元测试；依赖真实剪贴板/键盘的部分
  靠 `--dry-run` 和手动验证，不写脆弱的集成测试。
- 测试真实键入时，先复制无害的测试文本；不要把测试用剪贴板内容写进文档或 commit。
- **真机键入测试前先确认屏幕未锁定**：锁屏时模拟按键静默丢失、`activate` 无效、
  引擎照样退出 0，看起来像代码 bug。用 `CGSessionCopyCurrentDictionary()` 的
  `CGSSessionScreenIsLocked` 判断（见 PROGRESS 2026-09-11）。
- 键入类测试必须先把焦点固定到测试窗口（TextEdit 新文档），否则会打进用户当前
  聚焦的任意窗口。
