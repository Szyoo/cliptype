# PROGRESS.md — cliptype 进度记录

> 最新在上；绝对日期；记录实质进展、技术决策、卡点。规则见 [AGENTS.md](AGENTS.md)。

## 2026-09-12

- **窗口最小高度过大（用户反馈）**：SettingsView 的 `fixedSize(vertical:)` + 场景
  `windowResizability(.contentSize)` 把窗口撑到内容全高且不可缩。改为
  `.contentMinSize` + `defaultSize(480×640)` + 视图 `minHeight`（主窗 360 / 设置 320），
  grouped Form 自带滚动。用 debug 构建验证（480×640 → 可缩至 460×388、钳住不再缩 →
  可拉到 900），**没有重新打包 dist**，避免再次让用户刚授好的权限失效。
  用户问"UI 是原生的吗"：是，纯 SwiftUI 系统控件，自动套用当前 macOS 设计语言。

## 2026-09-11

- **v0.1.2 发布**（用户拍板）：https://github.com/Szyoo/cliptype/releases/tag/v0.1.2 ——
  权限检测修复 + 陈旧 TCC 记录引导。10 个产物齐全；Release 正文首次由
  `scripts/release-notes.sh` 从 CHANGELOG 生成（中英并列），CI 路径验证通过。
- **剪贴板历史：基础框架完成**（用户要求；UI 形态弹窗/面板待定，先打基础）。
  [ClipboardHistory.swift](app/macos/Sources/CliptypeApp/ClipboardHistory.swift)：
  `ClipEntry` + `ClipboardHistory` 单例；0.5s 轮询 `NSPasteboard.changeCount`（macOS
  无变更通知）；去重移顶；上限 20/50/100 条、单条 100 KB；跳过 concealed/transient
  类型；持久化 `~/Library/Application Support/Cliptype/history.json`（0700/0600、原子写）；
  **默认关闭**。API：`copyToPasteboard` / `type`（走引擎新 `--stdin`）/ `remove` / `clear`。
  设置窗口「剪贴板历史」分区 + 菜单栏子菜单占位（最近 15 条，点选回填剪贴板）。
  三语文案同步。详见 implementation-plan Phase 6。
  - 验证：复制 4 段（含重复）→ 3 条、顺序正确、密码管理器 concealed 项被跳过、
    文件 0600 / 目录 0700；子菜单列出条目、点选后剪贴板正确回填；`--stdin --dry-run`
    读取正确。`--stdin` 实际键入于 2026-09-12 解锁后补验通过（TextEdit 输出一字不差）。
  - 2026-09-12 用户本机也复现了"陈旧 TCC 记录"：用户在我重新打包（历史框架）之后拨开
    的开关，登记的是上一次弹窗时的旧签名，新构建匹配不上；用户自行重新授权后，
    新实例正确显示已授权，热键键入正常。教训：**用户授权流程进行中不要重新打包**；
    开发期最好配自签证书（`CODESIGN_ID`）让签名稳定。
  - **测试坑：Mac 锁屏时所有模拟键入静默失败**（`CGSessionCopyCurrentDictionary` 的
    `CGSSessionScreenIsLocked=true`；`activate` 无效、System Events 查不到前台进程），
    引擎仍正常退出 0，极易误判为代码 bug。本轮排查了半小时才发现是用户离开锁屏了。
    以后真机键入测试前先跑 `swift scratchpad/session.swift` 之类确认未锁屏。
- **客户报告：从 0.1.0 应用内更新到 0.1.1 后，辅助功能开关开着却"获取不到"权限；
  开关关掉再开无效，最后 − 删除条目再 + 加回来才好。** 排查出两个叠加的 bug：
  1. **TCC 记录陈旧（根因）**：ad-hoc 签名每次构建的 cdhash 不同；更新替换 .app 后，
     TCC 里的旧记录仍绑定旧签名指纹，开关只改 auth 标志、不更新指纹 → 新版永远
     匹配不上。更新助手里的 `tccutil reset Accessibility <bundle-id>` 对路径键控的
     记录可能删不掉（客户机上即如此），只有 − / + 重建记录才行。修复：设置窗口权限区
     常驻这套步骤 + 「帮我删除失效的条目」按钮；更新后 12 秒仍无权限则弹出明确的
     − / + 引导（PermissionHelper.presentStaleRecordHelp）。
  2. **`AXIsProcessTrusted()` 进程内缓存（加重问题）**：实测在本机 `tccutil reset`
     撤销后，运行中的 App 仍报 trusted；反过来客户授权后 App 仍报 untrusted。之前的
     2 秒轮询因此形同虚设，用户会以为授权没成功而反复折腾。修复：引擎新增
     `--check-permission`（退出码 0/1），App 每 2 秒（已授权时每 10 秒）起一个新进程
     查询——新进程会重新问 tccd，且子进程的责任进程是 App 本体，判定对象正确。
  3. 顺带：openSystemSettings 改为多 URL 方案顺序尝试（跨 macOS 版本）。
  - 用户提问"为什么有的权限能直接点允许，辅助功能却要手动进设置"：系统限制。
    辅助功能/输入监控/屏幕录制/完全磁盘访问是高危权限，Apple 不提供一键允许，
    应用只能弹带「打开系统设置」的引导框；无法自定义。已写进 README。
  - 验证：本机撤销权限 → 新版 App 正确显示未授权（旧版会卡在 trusted）。授权后
    的实时检测需要用户在系统设置里拨开关（agent 无法也不应代点），等用户操作确认。
  - 注意：诊断过程中我在用户机器上执行了 `tccutil reset`，撤销了 Cliptype 的权限，
    需要用户重新授权一次。
- **Release 正文改为 CHANGELOG 文本 + CHANGELOG 双语化**（用户反馈"为啥指向 commit"）。
  原因：release.yml 用了 `generate_release_notes: true`，GitHub 只会罗列 commit/PR。
  改为 [scripts/release-notes.sh](scripts/release-notes.sh) 从 CHANGELOG 抽取该版本
  小节（中英并列 + 完整日志链接），workflow 里 `body_path` 传入（release job 原本
  没有 checkout，一并补上）。CHANGELOG 按 README 惯例拆成 CHANGELOG.md（中文默认）
  + CHANGELOG.en.md，顺手修好了 0.1.0 段落里掉出小节标题的一批条目。已回填 v0.1.0
  和 v0.1.1 两个 Release 的正文。注意：这段文本也会显示在应用内更新弹窗里。
- **v0.1.1 发布**（用户拍板）：https://github.com/Szyoo/cliptype/releases/tag/v0.1.1
  内容 = VNC/远程控制台修复（`--mode keycode`）+ 应用图标 + 应用内更新。10 个产物
  （macOS app universal zip + 四平台 CLI，各带 sha256）全部构建成功。这是应用内更新
  首次面对真实 Release：用户机器上的 0.1.0 开发版通过菜单「检查更新」→ 下载校验 →
  替换重启，升级为官方 v0.1.1（universal、临时目录清理干净）。
  - **新发现：TCC 保护文件夹会卡住替换**。App 以自身身份（`open`）启动时，若 .app 位于
    ~/Documents、~/Desktop、~/Downloads，助手的 `rm -rf` 会触发系统"访问文件夹"询问并
    阻塞到用户点允许（此前测试都从终端启动、继承了沙盒权限所以没暴露）。/Applications
    不受影响。缓解：「准备安装」弹窗检测到受保护路径时追加提示（点允许 / 建议放
    应用程序文件夹），三语同步；README 安装教程本来就要求拖到应用程序。此改动进下一版。
- **应用内更新功能**（用户要求，"很多 macOS 软件都有"）。方案：不用 Sparkle（需要
  EdDSA 密钥 + appcast 运维，对 ad-hoc 签名阶段过重），直接对接 GitHub Releases API，
  复用现有发布产物和 `.sha256`。[Updater.swift](app/macos/Sources/CliptypeApp/Updater.swift)：
  - 启动 5s 后静默检查 + 每 24h 一次（设置可关），菜单栏「Check for Updates…」/
    设置「Check Now…」手动检查；设置里显示当前版本与状态；菜单栏标题行和主窗口
    头部也显示版本号。
  - 发现新版 → NSAlert 显示更新说明（下载并安装 / 以后 / 跳过此版本）→ 下载
    `*-macos-app-universal.zip` → 对照同 Release 的 `.sha256`（CryptoKit）→ `ditto -x -k`
    解压 → 「准备安装」确认 → 写入 bash 助手并启动 → 主进程退出 → 助手等 PID 消失后
    `rm -rf` 旧 .app、`mv` 新 .app、清 quarantine、`tccutil reset` 本 bundle id、
    `open` 重启、清理临时目录。重启后一次性重新弹辅助功能授权
    （`promptPermissionOnNextLaunch`）。
  - 安全装置：只替换 `.app` 且父目录可写（否则提示移到应用程序文件夹）；sha256 不匹配
    直接失败。
  - 验证：`APP_VERSION=0.0.9` 伪装旧版 → 自动发现 v0.1.0 → UI 脚本点两个按钮 →
    dist/Cliptype.app 变为 0.1.0 并重启、无 quarantine、临时目录已清理。手动检查在
    最新版上弹「已是最新」。
  - 已知限制：ad-hoc 签名下每次更新都要重新授权辅助功能（有 Developer ID 后消失）；
    资产文件名后缀 `-macos-app-universal.zip` 与 release.yml 耦合。
- **Bug 修复：VNC 控制台里全部打成 "a"**（用户报告）。根因：enigo 的 `text()` 把
  Unicode 字符串附加在**键码固定为 0**（US 布局 = A）的 CGEvent 上；本机应用读
  Unicode 字符串所以正常，VNC/远程控制台/VM 只转发物理键码 → 每个字符都是 a。
  enigo 自带的 `Key::Unicode` 键码路径也不可用：查到键码后不按 Shift、查不到返回
  0、字符缓冲区只有 1 字节。修复：
  1. 新增 [src/keymap.rs](src/keymap.rs)（macOS）：用 Carbon `UCKeyTranslate` 遍历
     当前键盘布局 0..127 键码 ×（无/Shift/Option/Option+Shift）建 字符→键码 表；
     `AsciiInputSourceGuard` 在发送期间 `TISSelectInputSource` 切到 ASCII 输入源、
     drop 时恢复（否则中文 IME 会截胡实键按下）。
  2. typer 新增 `InputMode::Keycode`：实键 + 修饰键（enigo `raw()` + Shift/Alt
     Press/Release，出错也保证释放修饰键）；布局上没有的字符回退 Unicode 并警告
     一次。非 macOS 走 enigo `Key::Unicode`（Windows 用 VkKeyScan 尚可）。
  3. CLI `--mode unicode|keycode`（默认 unicode）贯通单次/热键/托盘；托盘菜单加
     "Remote console mode" 勾选项并持久化（config 新增 `keycode_mode`）；Swift App
     设置窗口新增"兼容性"分区 + 菜单栏开关，三语文案同步，引擎调用传 `--mode`。
  - 验证：TextEdit 中 `Hello World! Foo_bar=42 {x}\tTab\nEND 日本` 键码模式输出
    完全一致（含大小写/符号/Tab/换行），中文按预期回退，微信输入法在发送后恢复。
  - 设计取舍：unicode 仍为默认（任意字符 + IME 免疫），keycode 需要用户显式开启，
    因为它受布局限制且本机与远端布局不一致时符号会错位（这一点无法在本端解决）。

## 2026-08-12

- **应用图标完成**：设计 = 蓝色渐变 squircle + 白色剪贴板 + 输入光标（剪贴板→键入的
  意象）。源文件 [assets/appicon.svg](assets/appicon.svg)，
  [scripts/make-icon.sh](scripts/make-icon.sh) 用纯系统工具（qlmanage 栅格化 +
  sips 缩放 + iconutil 打包）生成 app/macos/AppIcon.icns（10 尺寸），bundle 脚本
  同捆并在 Info.plist 声明 CFBundleIconFile。README 顶部同时展示。
  备忘：机器上没有 rsvg/imagemagick，qlmanage -t 可栅格化 SVG，够用。

## 2026-08-07

- **v0.1.0 正式发布**（用户亲自验证 App 后拍板）：
  https://github.com/Szyoo/cliptype/releases/tag/v0.1.0 ——六个产物全部构建成功
  （macOS app universal zip + CLI 三平台四包 + sha256），已下载 app 包核验：
  双架构 fat binary、三语 lproj 齐全、签名标识正确。CHANGELOG 0.1.0 定稿。
- **发行与文档重构（用户要求）**：
  1. README 改为**中文默认**（README.md 中文 + README.en.md 英文镜像）。
  2. 安装章节明确区分 macOS 两种方式并各配教程：方式一装 Cliptype.app（授权
     Cliptype 一处）；方式二终端 CLI（授权终端 App）。两种授权互相独立。
  3. Release 增加 macOS 应用打包物：`bundle-macos.sh` 支持 `BUILD_UNIVERSAL=1`
     （rust 双 target + lipo，swift `--arch arm64 --arch x86_64`），release
     workflow 新增 build-macos-app 任务，产出
     `cliptype-<tag>-macos-app-universal.zip`（ditto 打包 + sha256）。
- **国际化（用户要求）**：
  1. README 双语：README.md（英）+ README.zh-CN.md（中），顶部互链切换。
  2. App 界面本地化 en/zh-Hans/ja：SwiftPM `defaultLocalization` + `Resources/*.lproj`
     + `L()` 助手（键=英文原文，`Bundle.module` 查找），bundle 脚本同捆
     `CliptypeApp_CliptypeApp.bundle`，Info.plist 声明 CFBundleLocalizations。
     已实测：`--args -AppleLanguages "(zh-Hans)"/"(ja)"` 菜单分别显示中/日文。
     字体无需处理——macOS 系统字体自带全语言覆盖。
- **App 形态调整（用户反馈）**：
  1. 增加**应用本体主窗口**（状态头部 + 设置表单），去掉 LSUIElement——现在是常规
     应用：Dock 有图标、启动显示窗口、关窗后菜单栏继续常驻、点 Dock 或菜单
     "Open Cliptype…" 重开窗口（WindowGroup 的标准 reopen 行为）。
  2. **授权弹窗不再每次启动自动弹**：只在"从未授权过"的首次使用弹（UserDefaults
     记录 hasEverBeenTrusted）。重打包导致授权失效的场景不再突袭弹窗，由菜单警告
     项（点击会触发系统弹窗+打开系统设置）和设置窗口引导。
- **修复：授权后菜单栏仍显示"授予权限"警告**（用户实测发现）。两个叠加原因：
  1. UI bug：菜单内容里直接调用 `AXIsProcessTrusted()`，不是可观察状态，权限变化
     后 MenuBarExtra 不会重新渲染（Settings 窗口因后打开而显示正确）。修复：权限
     状态提升为 AppState 的 `@Published var axTrusted`，2 秒轮询刷新（授权/撤销
     都能反映）。
  2. TCC 陷阱：ad-hoc 签名每次重新打包 cdhash 都变，macOS 视为不同应用，**之前的
     授权直接失效**（系统设置里开关看似还开着但不生效）。缓解：bundle 脚本支持
     `CODESIGN_ID` 环境变量（自签证书可保持授权跨构建有效）；ad-hoc 时脚本提示用
     `tccutil reset Accessibility io.github.szyoo.cliptype` 清掉陈旧条目再重新授权。
- **方向修正（用户）+ Phase 5 macOS 原生应用骨架完成**：CLI 定位改为"功能验证 +
  Linux 形态"，最终产品是平台原生应用；macOS 要"应用本体（设置窗口）+ 常驻菜单栏"。
  - 架构决定：SwiftUI App（`app/macos/`，SwiftPM）负责 UI/热键/权限引导，Rust 二进制
    同捆为键入引擎（按热键时以 `--delay 0` 单次模式调用）。键入的坑（IME/尾部丢字/
    换行 Tab）留在 Rust 一处，Swift 不重复实现。TCC 只需授权 Cliptype.app 一处。
  - `scripts/bundle-macos.sh` → dist/Cliptype.app（LSUIElement 菜单栏应用、ad-hoc 签名）。
  - 已端到端验证：模拟 ⌃⇧V → Carbon 热键 → 等修饰键松开 → 引擎 → TextEdit 键入
    正确（日文/emoji）。菜单栏图标、Settings 窗口、暂停/速度切换就绪。
  - 调试备忘：`log show --predicate` 看不到 NSLog 的场景下，直接在终端跑
    `Cliptype.app/Contents/MacOS/CliptypeApp` 从 stderr 看日志最快。
  - 待办：应用图标、任意热键录制、开机自启、release 产物集成、Windows 原生界面。

- **v0.1.0 发布撤回**（用户反馈：尚未亲自验证，不到 release 的程度——发布这类对外
  动作以后必须先经用户确认）。GitHub Release 与 tag 均已删除，CHANGELOG 回退为
  Unreleased。release workflow 本身保留且已验证可用，等用户真机验证后重新打 tag。
  工件格式决定：CLI 阶段维持 tar.gz/zip 内置裸二进制（ripgrep/gh 等同款惯例；
  Windows zip 里就是 cliptype.exe）；.pkg/.msi 安装器需要付费签名证书否则
  Gatekeeper/SmartScreen 警告更吓人，列为远期可选项。
- **Phase 4 发布准备完成（基础设施）**：
  - `--speed fast|normal|slow` 预设（映射 0/20/50ms，与托盘菜单一致；与 `--interval`
    互斥，clap conflicts_with，带单元测试）。
  - [release.yml](.github/workflows/release.yml)：`v*` tag 触发，四个 target
    （macOS arm64/x64 + Windows x64 + Linux x64），macOS/Windows 带 tray，Linux 带
    hotkey；tar.gz/zip + sha256，softprops/action-gh-release 建 Release。
  - CHANGELOG Unreleased → 0.1.0。crates.io / Homebrew 暂缓（计划里本来就是可选）。
- **Phase 3.5 状态栏/托盘 UI 实装完成并 macOS 全链路真机验证**（`--features tray`）。
  用户决策：macOS/Windows 各自原生界面、打包互不包含对方——用 tray-icon（各平台
  原生 API 薄封装）+ Cargo target-specific dependencies 天然满足；Linux 不支持托盘
  （GTK 依赖太重），CLI/热键模式不受影响。实现要点：
  1. **菜单状态必须主线程改**：引入 tao 事件循环（tray 特性专用依赖），
     `MenuEvent::set_event_handler` → `EventLoopProxy::send_event` 回主线程处理；
     托盘图标须在 `StartCause::Init` 后创建；`ActivationPolicy::Accessory` 隐藏 Dock。
  2. global-hotkey 在 tao 的 NSApp 事件循环下正常触发（与 Carbon
     RunApplicationEventLoop 等效，验证过）。
  3. 菜单：热键显示 / Pause（CheckMenuItem 点击自动翻转，读 is_checked 即可）/
     速度预设 Fastest·20ms·50ms（手动 radio）/ Quit。图标是代码画的 32x32 键盘
     glyph（macOS template image 自动适配深浅色，无外部资源）。
  4. 设置持久化 [src/config.rs](src/config.rs)：std 手写 key=value（带单元测试），
     `~/.config/cliptype/config.toml`；interval 决定顺序 = CLI 非零值 > 配置 > 0。
  验证（AppleScript UI automation）：图标出现、菜单结构、Pause 后热键无输出、
  恢复后正常、切速度写盘、Quit 干净退出。Windows 侧编译由 CI 覆盖，待实机验证。
- **Phase 3 常驻热键模式实装完成并真机验证**（`--features hotkey`）。
  `cliptype --hotkey [COMBO]`，默认 `ctrl+shift+v`，组合键字符串用 global-hotkey 的
  FromStr（支持 `ctrl+shift+v` 简写）。结构：主线程注册 + 跑平台事件循环，worker
  线程收 crossbeam channel 事件，每次按下现读剪贴板→键入；单次失败只打日志不退出。
  两个关键实现点：
  1. **macOS 事件循环必须用 Carbon 的 `RunApplicationEventLoop()`**，不能用裸
     `CFRunLoopRun()`——global-hotkey 把 handler 装在 `GetApplicationEventTarget()`
     上，裸 run loop 不分发应用目标事件（实测：CFRunLoopRun 下热键完全无响应）。
  2. **键入前等修饰键松开**：macOS 轮询 `CGEventSourceFlagsState`（HID 状态，上限
     2s + 50ms 余量），其他平台固定等 300ms，避免用户还按着 Ctrl/Shift 时合成事件
     被物理修饰键污染。
  验证：AppleScript System Events 模拟 ctrl+shift+v（合成按键能触发
  RegisterEventHotKey），TextEdit 中两次触发均正确键入（含日文/emoji）。
  CI 增加 `--features hotkey` 构建与 `--all-features` clippy/test。
- **TCC 授权排查（用户在 Claude Code 桌面 App 内置终端测试）**：辅助功能授权按
  "责任 App"归属，Claude 桌面版有两个独立 TCC 主体——主应用 `/Applications/Claude.app`
  （用户终端的 shell 挂在它下面）和内嵌 CLI `…/Application Support/Claude/claude-code/…/claude.app`
  （agent 工具进程挂在它下面）。只授权其中一个时会出现"agent 能打字、用户终端不能"。
  解决：在辅助功能列表把两个都启用，或改用 Terminal.app/iTerm 并给其授权。
  这也验证了 `ensure_permission()` 报错路径在真实用户场景下正常工作。
- **真实键入端到端验证通过**（用户授权辅助功能后，agent 用 AppleScript 驱动 TextEdit
  自动化验证：键入 → 读回 → 比对 → 关闭不保存）。快速模式 3/3、逐字符模式 1/1 内容完整。
  过程中发现并修复两个真实 bug：
  1. **尾部丢字（竞态）**：发送完最后一个 CGEvent 后进程立即退出，未投递的事件随进程
     消失，偶发丢失最后一段文本（enigo 块间只 sleep 2ms）。修复：type_text 结束前
     等待 120ms 再返回。
  2. **逐字符模式被 IME 截胡**：`Key::Unicode` 模拟物理键码，活跃的中文 IME 会拦截
     组词（实测「日本語」→「啊啊啊」，空格/emoji 全丢）。修复：逐字符模式改用与快速
     模式相同的 `text()`（unicode 字符串附加事件，IME 素通り），一次发一个字符。
  - 已知无害现象：TextEdit 富文本模式的自动首字母大写会把行首小写字母改成大写
    （line2→Line2），属于目标应用的替换功能，与 cliptype 无关；纯文本框不受影响。
- **用户实测发现关键坑：未授权时静默失败**。真实键入测试"什么都没输入、无报错、正常退出"。
  根因：enigo 0.2.1 在 macOS 上**完全不检查辅助功能权限**（源码里没有 AXIsProcessTrusted），
  未授权时 CGEvent 被 OS 静默丢弃。修复：typer.rs 增加 `ensure_permission()`
  （直接 FFI 调 ApplicationServices 的 `AXIsProcessTrusted`，无新依赖），main 在倒计时前
  就检查，未授权立即报错并给出授权+重启终端的指引。已在沙盒（未授权环境）端到端验证
  报错路径正确。注意：授权后必须完全退出并重开终端 App 才生效（README 已写明）。
- **Phase 1 核心功能实装完成**：
  - `clipboard::read_text()` — arboard；空/非文本返回空字符串由 main 友好提示，不报错。
  - `typer::type_text()` — enigo；`interval==0` 走批量 `text()` 快速模式，`>0` 逐字符
    （`Key::Unicode`）+ sleep。改行/Tab 一律作为真实 Return/Tab 键发送
    （混在 `text()` 里部分应用不识别）。
  - 换行归一化 `normalize_newlines()`（CRLF/CR → LF）纯函数 + 5 个单元测试。
  - macOS 键盘错误附加辅助功能授权引导；错误信息不含剪贴板内容（设计原则）。
  - 用户可见文案（--help、运行时提示）从日语改为英文，符合 AGENTS.md 语言规范。
- **dry-run 端到端验证通过**（macOS 本机）：日文/emoji/Tab/CRLF/LF 混合文本 40 字符
  全部正确读取。真实键入验证（需辅助功能授权 + 手动操作）留给用户做。
- 踩坑记录：测试时 pbcopy 吞掉含多字节字符的内容，原因是 agent 沙盒 shell 未设 locale
  （`LANG` 空）；`export LC_ALL=en_US.UTF-8` 解决。与 cliptype 本身无关。
- 下一步：用户手动验证真实键入（TextEdit/浏览器）→ Phase 2 权限失败模式实测。

## 2026-07-21

- 修复首次 CI 失败：三平台都挂在 `cargo fmt --check`（main.rs 一行过长），本地
  `cargo fmt` 修复；顺带给 stub 阶段未读取的 `TypeOptions.interval` 加临时
  `#[allow(dead_code)]`（CI clippy 带 `-D warnings`，Phase 1 实装后移除）。
  本地已通过 fmt/clippy/build/test 全部四步。开发机新装了 rustup 稳定版工具链。
- 制定项目文档体系：AGENTS.md（权威指引）、CLAUDE.md（精简镜像）、
  [docs/implementation-plan.md](docs/implementation-plan.md)（分 4 个 Phase 的实施计划）、本文件。
- 确定核心设计原则：绝不在输出中泄露剪贴板内容（`--dry-run` 除外）；
  语言规范为对话中文 / 注释日语 / commit 与用户可见文本英文。
- 仓库已推送到 GitHub（https://github.com/Szyoo/cliptype ，分支 `main`），
  占位符 USERNAME 已替换为 Szyoo，CI（三平台 fmt+clippy+build+test）已触发。
- 当前状态：脚手架完成；`clipboard::read_text()` 和 `typer::type_text()` 仍是
  `bail!` 的 stub。下一步：Phase 1（实装这两个函数 + 换行归一化 + macOS 实测）。
