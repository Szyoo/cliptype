//! macOS: 現在のキーボード配列で「文字 → 物理キーコード + 修飾キー」を求める。
//!
//! VNC / リモートコンソール / VM のコンソールは、CGEvent に添付された Unicode
//! 文字列を無視して物理キーコードだけを転送する。`text()` 方式はキーコードを
//! 0（US 配列の "a"）に固定するため、そうした環境では全文字が "a" になる。
//! 本モジュールで実キーコードを引き、`typer` が実キー押下として送信する。

use anyhow::{anyhow, Result};
use std::collections::HashMap;
use std::ffi::c_void;
use std::thread;
use std::time::Duration;

type CFTypeRef = *const c_void;
type CFStringRef = CFTypeRef;
type CFDataRef = CFTypeRef;
type TISInputSourceRef = CFTypeRef;

#[link(name = "Carbon", kind = "framework")]
extern "C" {
    static kTISPropertyUnicodeKeyLayoutData: CFStringRef;
    fn TISCopyCurrentKeyboardLayoutInputSource() -> TISInputSourceRef;
    fn TISCopyCurrentKeyboardInputSource() -> TISInputSourceRef;
    fn TISCopyCurrentASCIICapableKeyboardInputSource() -> TISInputSourceRef;
    fn TISSelectInputSource(source: TISInputSourceRef) -> i32;
    fn TISGetInputSourceProperty(source: TISInputSourceRef, key: CFStringRef) -> CFTypeRef;
    fn LMGetKbdType() -> u8;
    fn UCKeyTranslate(
        layout: *const c_void,
        virtual_key: u16,
        key_action: u16,
        modifier_key_state: u32,
        keyboard_type: u32,
        options: u32,
        dead_key_state: *mut u32,
        max_len: usize,
        actual_len: *mut usize,
        out: *mut u16,
    ) -> i32;
}

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFDataGetBytePtr(data: CFDataRef) -> *const u8;
    fn CFEqual(a: CFTypeRef, b: CFTypeRef) -> u8;
    fn CFRelease(cf: CFTypeRef);
}

/// kUCKeyActionDisplay: 「このキーを押すと何が表示されるか」を問い合わせる
const KEY_ACTION_DISPLAY: u16 = 3;
/// kUCKeyTranslateNoDeadKeysMask: デッドキー状態を持ち越さない
const NO_DEAD_KEYS: u32 = 1;
/// UCKeyTranslate の modifierKeyState は EventRecord.modifiers >> 8
const MOD_SHIFT: u32 = 0x0200 >> 8;
const MOD_OPTION: u32 = 0x0800 >> 8;

/// 1 文字を打つための物理キーと修飾キー。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyStroke {
    pub keycode: u16,
    pub shift: bool,
    pub option: bool,
}

/// 現在のキーボード配列から作った「文字 → KeyStroke」表。
pub struct LayoutMap {
    map: HashMap<char, KeyStroke>,
}

impl LayoutMap {
    /// 現在の配列を走査して表を作る。修飾なし → Shift → Option → Option+Shift の
    /// 順に見て、最初に見つかった（最も単純な）組み合わせを採用する。
    pub fn current() -> Result<Self> {
        // SAFETY: Carbon TIS / UCKeyTranslate の呼び出し。source は Copy ルールで
        // 所有権を得るので最後に CFRelease する。layout data は Get ルールで
        // source が所有しており、source を解放するまで有効。
        unsafe {
            let source = TISCopyCurrentKeyboardLayoutInputSource();
            if source.is_null() {
                return Err(anyhow!("could not determine the current keyboard layout"));
            }
            let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
            if data.is_null() {
                CFRelease(source);
                return Err(anyhow!(
                    "the current keyboard layout exposes no key layout data"
                ));
            }
            let layout = CFDataGetBytePtr(data) as *const c_void;
            let kbd_type = u32::from(LMGetKbdType());

            let mut map = HashMap::new();
            let combos = [
                (0, false, false),
                (MOD_SHIFT, true, false),
                (MOD_OPTION, false, true),
                (MOD_SHIFT | MOD_OPTION, true, true),
            ];
            for (mods, shift, option) in combos {
                for keycode in 0u16..128 {
                    let mut dead_state = 0u32;
                    let mut len = 0usize;
                    let mut buf = [0u16; 4];
                    let status = UCKeyTranslate(
                        layout,
                        keycode,
                        KEY_ACTION_DISPLAY,
                        mods,
                        kbd_type,
                        NO_DEAD_KEYS,
                        &mut dead_state,
                        buf.len(),
                        &mut len,
                        buf.as_mut_ptr(),
                    );
                    // 1 文字（BMP）を生むキーだけ採用。制御文字（Return/Tab 等）は
                    // typer が専用キーで送るので除外する。
                    if status != 0 || len != 1 {
                        continue;
                    }
                    let Some(ch) = char::from_u32(u32::from(buf[0])) else {
                        continue;
                    };
                    if ch.is_control() {
                        continue;
                    }
                    map.entry(ch).or_insert(KeyStroke {
                        keycode,
                        shift,
                        option,
                    });
                }
            }
            CFRelease(source);
            Ok(Self { map })
        }
    }

    /// `ch` を打つキー。現在の配列に無い文字（CJK 等）は None。
    pub fn lookup(&self, ch: char) -> Option<KeyStroke> {
        self.map.get(&ch).copied()
    }
}

/// 送信中だけ入力ソースを ASCII 配列に切り替えるガード。drop で元に戻す。
///
/// IME（かな / ピンイン等）が有効なままだと実キー押下が変換に横取りされる
/// （実測: 中国語 IME で「日本語」→「啊啊啊」）。既に ASCII 配列なら何もしない。
pub struct AsciiInputSourceGuard {
    previous: TISInputSourceRef,
}

impl AsciiInputSourceGuard {
    pub fn activate() -> Option<Self> {
        // SAFETY: Copy ルールの参照はこちらで解放する。previous は drop まで保持。
        unsafe {
            let current = TISCopyCurrentKeyboardInputSource();
            let ascii = TISCopyCurrentASCIICapableKeyboardInputSource();
            if current.is_null() || ascii.is_null() {
                release_if_some(current);
                release_if_some(ascii);
                return None;
            }
            if CFEqual(current, ascii) != 0 {
                CFRelease(current);
                CFRelease(ascii);
                return None;
            }
            let status = TISSelectInputSource(ascii);
            CFRelease(ascii);
            if status != 0 {
                CFRelease(current);
                return None;
            }
            // 切り替えが入力コンテキストに反映されるまで少し待つ
            thread::sleep(Duration::from_millis(80));
            Some(Self { previous: current })
        }
    }
}

impl Drop for AsciiInputSourceGuard {
    fn drop(&mut self) {
        // SAFETY: previous は activate() で得た所有参照
        unsafe {
            TISSelectInputSource(self.previous);
            CFRelease(self.previous);
        }
    }
}

unsafe fn release_if_some(cf: CFTypeRef) {
    if !cf.is_null() {
        CFRelease(cf);
    }
}
