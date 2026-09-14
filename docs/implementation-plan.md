# Implementation Plan

按阶段推进；每个阶段完成后在 [PROGRESS.md](../PROGRESS.md) 记录并勾选。
与 README 的 Roadmap 对应，但这里是给开发用的细化版本。

## Phase 1: 核心 MVP（可用的 v0.1.0）

1. `clipboard::read_text()` — `arboard::Clipboard::new()?.get_text()`；
   剪贴板为空或非文本（`ContentNotAvailable`）时给出清晰的英文错误提示，不 panic。
2. `typer::type_text()` — `enigo::Enigo::new(&Settings::default())?`：
   - `interval == 0`：`enigo.text(&text)` 整段发送（最快，enigo 内部处理 Unicode）。
   - `interval > 0`：逐字符发送，字符间 sleep interval。
3. 换行归一化：键入前把 `\r\n` / `\r` 归一为 `\n`，避免 Windows 剪贴板文本在
   macOS/Linux 上多敲一次回车（抽成纯函数 + 单元测试）。
4. 本机验证：`cargo run -- --dry-run` → macOS 辅助功能授权 → 真实键入
   TextEdit/浏览器输入框（英文、日文、emoji、多行、Tab）。
5. 里程碑：macOS 上端到端可用，CHANGELOG 记 0.1.0。

## Phase 2: 跨平台健壮性

1. macOS 未授权辅助功能时的错误检测与引导信息（enigo 的失败模式实测确认）。
2. Windows / Linux(X11) 实机或 VM 验证 Unicode、换行、Tab 行为，平台差异记进
   AGENTS.md 平台注意事项。
3. 特殊字符边界情况：IME 干扰、目标应用吞字（interval 建议值写进 README）。
4. `--interval` 下的进度反馈（长文本时 stderr 显示进度，不显示内容本身）。

## Phase 3: 常驻热键模式（feature = `hotkey`）— ✅ 2026-07-22 完成

1. ✅ `--hotkey [COMBO]` 参数（仅 `--features hotkey` 编译时存在，默认 `ctrl+shift+v`）。
2. ✅ `global-hotkey` 事件循环。macOS 必须用 Carbon `RunApplicationEventLoop`
   （裸 CFRunLoopRun 不分发应用目标事件，详见 PROGRESS.md 2026-07-22）。
3. ✅ 常驻时按热键 = 等修饰键松开后立即"读剪贴板→键入"（`--delay` 在此模式无效）。
4. ✅ README 增加 hotkey 模式用法。

## Phase 3.5: 状态栏/托盘 UI（feature = `tray`，macOS/Windows）— ✅ 2026-07-22 完成

1. ✅ `--tray`：热键常驻 + 原生状态栏图标（tray-icon + tao，target-specific deps，
   两平台二进制互不包含对方 UI 代码；Linux 不支持托盘）。
2. ✅ 菜单：当前热键显示、Pause/Resume、打字速度预设（Fastest/20ms/50ms）、Quit。
3. ✅ 设置持久化：`~/.config/cliptype/config.toml`（Windows `%APPDATA%\cliptype\`），
   std 手写 key=value 解析（有单元测试），坏文件静默回退默认值。
4. ✅ macOS 全链路真机验证（图标、菜单、暂停/恢复、持久化、退出）。
   Windows 待实机验证。

## Phase 4: 发布与打磨 — 基础设施就绪，正式发布待用户亲自验证

1. ✅ GitHub Actions release workflow：打 tag → 四 target 二进制 + sha256 → Release
   （workflow 已用临时 tag 全流程验证过，产物可下载可运行，随后撤回）。
2. ✅ 打字速度预设：`--speed fast|normal|slow` 映射 0/20/50ms（与托盘菜单一致）。
3. ⬜ **v0.1.0 正式 tag：等用户在真机亲自验证单次/热键/托盘模式后再打。**
4. ⬜（可选）发布到 crates.io / Homebrew tap。
5. ✅ 2026-09-13 macOS 应用**自签证书签名**（"Cliptype Signing"，本地 + CI 同一套
   临时钥匙串流程）：签名要求跨版本稳定，应用内更新不再需要重新授权。
   ⬜ Apple Developer ID + 公证（消除 Gatekeeper 提示）；⬜ Windows 代码签名。

## Phase 5: 平台原生应用（最终形态）

> 方向修正（2026-07-22，用户）：CLI 只是功能验证手段和 Linux 形态，最终产品是
> macOS / Windows 的常驻应用。macOS 需要"应用本体（设置窗口）+ 常驻菜单栏"两者。
> 两平台界面各自独立维护，打包互不包含对方的东西。

**架构**：Swift 负责全部 UI/热键/权限引导；Rust `cliptype` 二进制作为键入引擎同捆在
.app 内（IME 迂回、尾部 flush、换行/Tab 处理不在 Swift 重复实现）。TCC 责任进程 =
App 本体，用户只需授权 Cliptype.app 一处，子进程引擎自动继承。

1. ✅ 2026-07-22 macOS SwiftUI App 骨架：`app/macos/`（SwiftPM，macOS 14+）——
   MenuBarExtra 菜单栏常驻（暂停/速度/设置入口/退出）+ Settings 设置窗口
   （热键预设、速度、权限状态）+ Carbon RegisterEventHotKey + 引擎调用
   （`--delay 0` 单次模式）+ 首启动辅助功能授权弹窗。
   `scripts/bundle-macos.sh` 组装 dist/Cliptype.app（LSUIElement、ad-hoc 签名）。
   已端到端验证（模拟热键 → TextEdit 键入正确）。
2. ⬜ 任意热键录制 UI（当前为预设列表）、开机自启（SMAppService）。
   ✅ 2026-08-12 应用图标：assets/appicon.svg 源 + scripts/make-icon.sh
   （qlmanage+sips+iconutil，纯系统工具）生成 app/macos/AppIcon.icns。
3. ✅ release workflow 产出 .app（universal zip）；✅ 2026-09-13 自签证书签名；⬜ Apple 公证 + dmg。
4. ⬜ Windows 原生界面（当前沿用 Rust tray exe 作为 Windows 界面）。

## Phase 6: 剪贴板历史（macOS 应用）

> 用户要求（2026-09-11）。UI 形态（弹窗 / 面板 / 菜单）待定，先把基础层打好。

**分层**：
- 基础层 ✅ 2026-09-11 [ClipboardHistory.swift](../app/macos/Sources/CliptypeApp/ClipboardHistory.swift)：
  `ClipEntry` 模型 + `ClipboardHistory` 单例（ObservableObject）。监视 = 0.5s 轮询
  `NSPasteboard.changeCount`；去重（相同内容移到顶部）；件数上限 20/50/100；单条上限
  100 KB；跳过 concealed / transient 类型（密码管理器约定）。持久化到
  `~/Library/Application Support/Cliptype/history.json`（目录 0700、文件 0600、原子写）。
  **默认关闭**，用户显式开启。
- 操作 API ✅：`copyToPasteboard(entry)`（放回剪贴板 → 用平时的热键输入）、
  `type(entry)`（直接键入，走引擎 `--stdin`，内容不经过剪贴板也不进进程参数）、
  `remove` / `clear`。
- 引擎 ✅：CLI 新增 `--stdin`（从标准输入读文本代替剪贴板）。
- 设置 ✅：「剪贴板历史」分区——开关 + 隐私说明 + 件数上限 + 已保存条数 + 清空。
- 占位 UI ✅：菜单栏子菜单列出最近 15 条（单行预览），点选放回剪贴板。

**UI 形态（2026-09-14 用户决定）**：✅ 热键呼出的**非激活浮动面板**
[HistoryPanel.swift](../app/macos/Sources/CliptypeApp/HistoryPanel.swift) /
[HistoryPanelView.swift](../app/macos/Sources/CliptypeApp/HistoryPanelView.swift)：
`NSPanel(.nonactivatingPanel)`，不调用 `NSApp.activate` → 目标应用焦点不丢（实测面板
打开时 frontmost 仍是 TextEdit）。1–9 / ↑↓ + Return 直接键入（引擎 `--stdin`）、⌘Return
复制、打字过滤、Esc / 失焦关闭。热键 id 2（默认 ⌃⇧H）。
位置策略 `PanelPosition`：statusItem（默认，取自进程内 `NSStatusBarWindow` 的 frame）/
caret（AX `kAXBoundsForRangeParameterizedAttribute`，取不到回退 statusItem）/ center /
custom（`isMovableByWindowBackground`，`didMoveNotification` 保存原点，重置按钮）。
菜单栏子菜单保留为鼠标备用入口。

**后续**：
1. ⬜ 面板内右键/滑动删除单条、置顶。
2. ⬜ 历史条目的直接键入热键（例如 ⌃⇧1…9 键入第 N 条）。
3. ⬜ 搜索 / 置顶 / 排除特定应用（如密码管理器、终端）。
4. ⬜ Windows 侧（Rust tray）对齐：可复用 history.json 格式。

## 已知风险

- enigo 0.2 在 macOS 对长文本 `.text()` 的可靠性未验证；不行就退回逐字符模式。
- Wayland 下 enigo/arboard 支持不完整，明确标注为 best-effort。
- 部分目标应用（远程桌面客户端）会在高速键入时吞字 → interval 是第一缓解手段。
