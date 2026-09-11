<p align="center"><img src="assets/appicon.svg" width="128" alt="cliptype"></p>

# cliptype

**简体中文** | [English](README.en.md)

把剪贴板内容以模拟键盘输入的方式"打"出来。

`cliptype` 读取剪贴板中的文本，然后像真人打字一样逐字符输入到当前焦点位置。
适用于禁止粘贴的输入框——远程桌面、虚拟机、部分密码框、自助终端软件等
<kbd>Ctrl/Cmd</kbd>+<kbd>V</kbd> 失效的场景。

跨平台：**macOS**（原生应用 + CLI）、**Windows**（托盘 + CLI）、**Linux**（CLI）。

> 状态：macOS 上已实现并验证；Windows / Linux 的运行时验证进行中。
> 见[路线图](#路线图)。

## 安装

所有安装包都在 [GitHub Releases](https://github.com/Szyoo/cliptype/releases) 页面。
macOS 用户有两种使用方式，**任选其一**：

### macOS · 方式一：安装应用（推荐）

图形界面 + 常驻菜单栏，适合日常使用。

1. 下载 `cliptype-vX.Y.Z-macos-app-universal.zip`（同时支持 Apple Silicon 和 Intel）。
2. 解压，把 **Cliptype.app** 拖入「应用程序」文件夹。
3. 应用暂未进行开发者签名，首次运行前先清除隔离标记（终端执行）：

   ```sh
   xattr -d com.apple.quarantine /Applications/Cliptype.app
   ```

4. 打开 Cliptype。首次启动会弹出授权引导：到**系统设置 → 隐私与安全性 →
   辅助功能**，给 **Cliptype** 打开开关（只需授权这一个条目，内置输入引擎
   自动继承）。
5. 复制一段文本 → 聚焦目标输入框 → 按 <kbd>⌃⇧V</kbd>。
   热键与打字速度可在主窗口 / 菜单栏图标 → 设置中修改。

### macOS · 方式二：终端 CLI

无图形界面，适合开发者和脚本场景。

1. 下载 `cliptype-vX.Y.Z-aarch64-apple-darwin.tar.gz`（Apple Silicon）
   或 `x86_64-apple-darwin`（Intel），解压得到 `cliptype`。
2. 清除隔离标记：`xattr -d com.apple.quarantine ./cliptype`
3. 授权对象是**运行它的终端 App**：到系统设置 → 辅助功能，加入并打开
   Terminal / iTerm 等你实际使用的终端，然后**完全退出并重开终端**。
4. 见下方[CLI 用法](#cli-用法)。

> 两种方式的授权互相独立：应用方式授权 Cliptype 本身；CLI 方式授权终端。
> 没有权限时 macOS 会静默丢弃模拟按键，cliptype 会检测并报错而不是假装成功。

### Windows

下载 `cliptype-vX.Y.Z-x86_64-pc-windows-msvc.zip`，解压得到 `cliptype.exe`，
无需额外配置。`cliptype.exe --tray` 启动托盘常驻模式。

### Linux

下载 `cliptype-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz` 解压即用（X11；
Wayland 取决于合成器，XWayland 一般可用）。运行时需要 `libxdo`：

```sh
sudo apt-get install -y libxdo3   # Debian/Ubuntu 运行时
```

### 从源码构建

需要 [Rust 工具链](https://rustup.rs/)；macOS 应用另需 Xcode 命令行工具。

```sh
git clone https://github.com/Szyoo/cliptype
cd cliptype
cargo build --release            # CLI，二进制在 target/release/cliptype
scripts/bundle-macos.sh          # macOS 应用，产物在 dist/Cliptype.app
```

Linux 构建依赖：`libxdo-dev` 及 xcb 系列开发库（见 CI 配置）。

## CLI 用法

```
cliptype [OPTIONS]

Options:
  -d, --delay <MS>      开始输入前的延迟（毫秒）        [默认: 2000]
  -i, --interval <MS>   每个按键之间的间隔（毫秒）      [默认: 0]
  -s, --speed <SPEED>   打字速度预设  [可选值: fast, normal, slow]
  -m, --mode <MODE>     发送方式      [可选值: unicode, keycode]  [默认: unicode]
      --dry-run         只打印将要输入的内容，不实际输入
  -h, --help            显示帮助
  -V, --version         显示版本
```

`--speed` 是 `--interval` 的友好替代（fast = 无间隔，normal = 20 毫秒，
slow = 50 毫秒——适合高速输入会吞字的应用）。

`--mode` 决定按键的发送方式：

- `unicode`（默认）：以 Unicode 文本事件发送，任何字符都能打，不受输入法干扰，
  适合本机应用。
- `keycode`：按当前键盘布局逐字符按下**真实键码**。**VNC、远程控制台、虚拟机
  窗口必须用这个模式**——它们只转发物理键码、忽略附加的 Unicode 文本，否则每个
  字符都会变成 `a`。只能输入键盘布局上存在的字符（中日文等会回退为 Unicode 并
  给出警告）；发送期间会临时切到英文输入源并在结束后恢复。
  在 macOS 应用 / 托盘菜单里对应"远程控制台模式（VNC / 虚拟机）"开关。

```sh
# 复制一段文字，然后：
cliptype --delay 3000
# 3 秒内切换到目标窗口，剪贴板文本会被自动打出。
```

### 常驻热键模式（`--features hotkey`）

`cliptype --hotkey` 常驻运行，每次按热键就把当前剪贴板打出来——无需倒计时：

```sh
cliptype --hotkey                    # 默认组合键: ctrl+shift+v
cliptype --hotkey "alt+F9"           # 自定义组合键
cliptype --hotkey --interval 20      # 每次触发按逐字符模式输入
```

会等修饰键松开后再输入，组合键不污染输出。终端 <kbd>Ctrl</kbd>+<kbd>C</kbd> 退出。

### 状态栏 / 托盘模式（`--features tray`，macOS 和 Windows）

`cliptype --tray` 在热键模式之上增加状态栏图标：显示当前热键、暂停/恢复、
切换速度（持久化到 `~/.config/cliptype/config.toml`，Windows 为
`%APPDATA%\cliptype\`）。macOS 日常使用建议直接用原生应用（方式一）。

## 路线图

- [x] 剪贴板读取与键盘输入发送（Unicode / 换行 / Tab，macOS 已验证）
- [ ] Windows / Linux 运行时验证
- [x] 常驻热键模式（`--features hotkey`）
- [x] 状态栏 / 托盘 UI（`--features tray`，macOS 和 Windows）
- [x] macOS 原生应用（主窗口 + 菜单栏，界面中/英/日三语）
- [x] 预编译发布：CLI 三平台 + macOS 应用（universal）
- [ ] 应用签名与公证（Apple Developer 证书后）
- [ ] Windows 原生界面

## 参与贡献

欢迎 Issue 和 Pull Request。提交前请运行 `cargo fmt` 和 `cargo clippy`。

## 许可证

[MIT](LICENSE)
