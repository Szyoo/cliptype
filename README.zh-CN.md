# cliptype

[English](README.md) | **简体中文**

把剪贴板内容以模拟键盘输入的方式"打"出来。

`cliptype` 读取剪贴板中的文本，然后像真人打字一样逐字符输入到当前焦点位置。
适用于禁止粘贴的输入框——远程桌面、虚拟机、部分密码框、自助终端软件等
<kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> 失效的场景。

跨平台：**macOS**、**Windows**、**Linux**。

> 状态：核心功能与可选的常驻热键模式已在 macOS 上实现并验证，
> Windows / Linux 的运行时验证进行中。见[路线图](#路线图)。

## 工作原理

1. 读取当前剪贴板文本（[`arboard`](https://crates.io/crates/arboard)）。
2. 等待一段可配置的延迟，给你时间切换到目标窗口。
3. 把文本作为键盘输入发送（[`enigo`](https://crates.io/crates/enigo)）。

## 用法

```
cliptype [OPTIONS]

Options:
  -d, --delay <MS>      开始输入前的延迟（毫秒）        [默认: 2000]
  -i, --interval <MS>   每个按键之间的间隔（毫秒）      [默认: 0]
  -s, --speed <SPEED>   打字速度预设  [可选值: fast, normal, slow]
      --dry-run         只打印将要输入的内容，不实际输入
  -h, --help            显示帮助
  -V, --version         显示版本
```

`--speed` 是 `--interval` 的友好替代（fast = 无间隔，normal = 20 毫秒，
slow = 50 毫秒——适合高速输入会吞字的应用）。

示例：

```sh
# 复制一段文字，然后：
cliptype --delay 3000
# 3 秒内切换到目标窗口，剪贴板文本会被自动打出。
```

### 常驻热键模式（可选）

以 `hotkey` feature 构建后，`cliptype --hotkey` 会常驻运行，每次按下热键就把
当前剪贴板打出来——无需倒计时、无需切换窗口，聚焦目标输入框按组合键即可：

```sh
cargo build --release --features hotkey

cliptype --hotkey                    # 默认组合键: ctrl+shift+v
cliptype --hotkey "alt+F9"           # 自定义组合键
cliptype --hotkey --interval 20      # 每次触发按逐字符模式输入
```

`cliptype` 会等热键的修饰键全部松开后再开始输入，组合键本身不会污染输出。
此模式下 `--delay` 无效。在终端按 <kbd>Ctrl</kbd>+<kbd>C</kbd> 退出。

### 状态栏 / 托盘模式（可选，macOS 和 Windows）

以 `tray` feature 构建后，`cliptype --tray` 在常驻热键模式之上增加状态栏
（菜单栏 / 系统托盘）图标：

- 显示当前生效的热键
- 暂停 / 恢复输入
- 切换打字速度——持久化到 `~/.config/cliptype/config.toml`
  （Windows 为 `%APPDATA%\cliptype\`），下次启动自动恢复

```sh
cargo build --release --features tray

cliptype --tray                     # 状态栏图标 + 默认热键
cliptype --tray --hotkey "alt+F9"   # 自定义组合键
```

UI 在每个平台都是原生实现——macOS 用 `NSStatusItem`，Windows 用通知区域——
且借助条件编译，每个平台的二进制只包含自己平台的 UI 代码。Linux 构建不含托盘；
CLI 和热键模式在所有平台可用。

### macOS 应用（菜单栏）

macOS 提供原生应用——这是 Mac 上使用 cliptype 的推荐方式。它把 Rust 二进制
作为输入引擎打包在内，提供菜单栏图标（暂停、打字速度、热键）和设置窗口：

```sh
scripts/bundle-macos.sh    # 需要 Rust 工具链和 Xcode 命令行工具
open dist/Cliptype.app
```

首次启动时应用会请求辅助功能权限——在系统设置中授权给 **Cliptype**
（一个条目同时覆盖内置引擎），然后重新启动应用。聚焦任意输入框，
按 <kbd>⌃⇧V</kbd>（可在设置中更改）。

## 平台说明

### macOS
模拟键盘输入需要**辅助功能**权限。在*系统设置 → 隐私与安全性 → 辅助功能*中，
把运行 `cliptype` 的终端 App 加入允许列表。授权后需要**完全退出并重新打开
终端 App**——已在运行的进程不会获得新权限。

没有该权限时，macOS 会静默丢弃模拟按键；`cliptype` 会检测到这种情况并报错退出，
而不是看似成功实际什么都没输入。

### Linux
X11 下 `enigo`/`arboard` 依赖 `libxdo` 和 X11 开发库。Debian/Ubuntu：

```sh
sudo apt-get install -y libxdo-dev libxcb1-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev
```

Wayland 支持取决于合成器；XWayland 一般可用。

### Windows
无需额外配置。

## 安装

每个 [GitHub Release](https://github.com/Szyoo/cliptype/releases) 附带 macOS
（Apple Silicon 和 Intel）、Windows、Linux 的预编译二进制。macOS 和 Windows
版本包含热键与托盘功能；Linux 版本包含热键模式。

macOS 下载后需清除隔离标记：

```sh
xattr -d com.apple.quarantine ./cliptype
```

## 从源码构建

需要 [Rust 工具链](https://rustup.rs/)。

```sh
git clone https://github.com/Szyoo/cliptype
cd cliptype
cargo build --release
# 二进制在 ./target/release/cliptype
```

## 路线图

- [x] 剪贴板文本读取（`clipboard::read_text`）
- [x] 键盘输入发送（`typer::type_text`）
- [ ] 跨平台验证 Unicode / 换行 / Tab 处理
- [x] 可选的常驻热键模式（`--features hotkey`）
- [x] 带设置的状态栏 / 托盘 UI（`--features tray`，macOS 和 Windows）
- [x] macOS / Windows / Linux 预编译二进制发布
- [x] 可配置的打字速度预设（`--speed`）

## 参与贡献

欢迎 Issue 和 Pull Request。提交前请运行 `cargo fmt` 和 `cargo clippy`。

## 许可证

[MIT](LICENSE)
