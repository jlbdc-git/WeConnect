// ============================================================
// WeConnect Windows runner — global PTT input hooks
// ============================================================
// Method channel "weconnect/platform":
//   Dart → native:
//     setPttHook    { vkCode: int, mouseXButton: int }  → install hooks
//     clearPttHook                                      → remove hooks
//     setPttEnabled { enabled: bool }                   → gate events
//   native → Dart (InvokeMethod "onPttEvent"):
//     { "type": "ptt", "down": true|false }
//
// WHY low-level hooks: WH_KEYBOARD_LL / WH_MOUSE_LL receive input for the
// whole desktop session, so PTT works even when the app is NOT focused —
// same as Discord. The hook proc must stay fast or Windows drops it, so
// it only forwards the event; all logic happens in Dart.
//
// LIFETIME: the channel object is heap-allocated once and leaked
// deliberately (process-lifetime singleton, same as the hooks); it is
// torn down with the rest of the process at exit. UnregisterPttHooks()
// removes the WH_*_LL hooks when the host window is destroyed so no
// dangling callbacks outlive the engine.
// ============================================================

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/plugin_registrar_windows.h>

#include <cstdint>
#include <memory>

namespace weconnect {

namespace {

flutter::MethodChannel<flutter::EncodableValue>* g_channel = nullptr;
HHOOK g_keyboard_hook = nullptr;
HHOOK g_mouse_hook = nullptr;
UINT g_vk_code = 0;
UINT g_mouse_xbutton = 0; // 0=none, 4=XBUTTON1, 5=XBUTTON2, 6=middle
bool g_ptt_enabled = false;

// Matches both 32-bit Dart-SmallInt encodings and 64-bit ones.
UINT ReadUIntFromEncodable(const flutter::EncodableValue& value) {
  if (const auto* v = std::get_if<int32_t>(&value)) {
    return static_cast<UINT>(*v);
  }
  if (const auto* v = std::get_if<int64_t>(&value)) {
    return static_cast<UINT>(*v);
  }
  return 0;
}

void SendPttEvent(bool down) {
  if (!g_channel) return;
  flutter::EncodableMap event;
  event[flutter::EncodableValue("type")] = flutter::EncodableValue("ptt");
  event[flutter::EncodableValue("down")] = flutter::EncodableValue(down);
  g_channel->InvokeMethod(
      "onPttEvent", std::make_unique<flutter::EncodableValue>(event));
}

LRESULT CALLBACK KeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_ptt_enabled) {
    const KBDLLHOOKSTRUCT* info =
        reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    const bool key_up = (wparam == WM_KEYUP || wparam == WM_SYSKEYUP);
    if (info->vkCode == g_vk_code) {
      SendPttEvent(!key_up);
      // Do NOT swallow the key: normal typing keeps working when focused.
    }
  }
  return CallNextHookEx(g_keyboard_hook, code, wparam, lparam);
}

LRESULT CALLBACK MouseProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && g_ptt_enabled && g_mouse_xbutton != 0) {
    const MSLLHOOKSTRUCT* info = reinterpret_cast<const MSLLHOOKSTRUCT*>(lparam);
    bool match = false;
    bool down = false;
    switch (wparam) {
      case WM_XBUTTONDOWN:
      case WM_XBUTTONUP: {
        const WORD hb = HIWORD(info->mouseData);
        const UINT xb = (hb & XBUTTON1) ? 4u : ((hb & XBUTTON2) ? 5u : 0u);
        match = (g_mouse_xbutton == xb);
        down = (wparam == WM_XBUTTONDOWN);
        break;
      }
      case WM_MBUTTONDOWN:
      case WM_MBUTTONUP:
        match = (g_mouse_xbutton == 6u);
        down = (wparam == WM_MBUTTONDOWN);
        break;
      default:
        break;
    }
    if (match) SendPttEvent(down);
  }
  return CallNextHookEx(g_mouse_hook, code, wparam, lparam);
}

void InstallHooks(UINT vk, UINT mouse_xbutton) {
  g_vk_code = vk;
  g_mouse_xbutton = mouse_xbutton;

  if (g_keyboard_hook) UnhookWindowsHookEx(g_keyboard_hook);
  if (g_mouse_hook) UnhookWindowsHookEx(g_mouse_hook);
  g_keyboard_hook = nullptr;
  g_mouse_hook = nullptr;

  if (vk != 0) {
    g_keyboard_hook = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardProc,
                                       GetModuleHandle(nullptr), 0);
  }
  if (mouse_xbutton != 0) {
    g_mouse_hook =
        SetWindowsHookEx(WH_MOUSE_LL, MouseProc, GetModuleHandle(nullptr), 0);
  }
  g_ptt_enabled = (g_keyboard_hook != nullptr) || (g_mouse_hook != nullptr);
}

void ClearHooks() {
  if (g_keyboard_hook) UnhookWindowsHookEx(g_keyboard_hook);
  if (g_mouse_hook) UnhookWindowsHookEx(g_mouse_hook);
  g_keyboard_hook = nullptr;
  g_mouse_hook = nullptr;
  g_ptt_enabled = false;
}

}  // namespace

void RegisterPlatformChannels(flutter::BinaryMessenger* messenger) {
  // Process-lifetime singleton: freed at process exit, after the engine is
  // gone. Kept alive so late hook events never touch a dangling pointer.
  auto* channel = new flutter::MethodChannel<flutter::EncodableValue>(
      messenger, "weconnect/platform",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel = channel;

  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "setPttHook") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      UINT vk = 0, mouse = 0;
      if (args) {
        if (const auto it = args->find(flutter::EncodableValue("vkCode"));
            it != args->end()) {
          vk = ReadUIntFromEncodable(it->second);
        }
        if (const auto it = args->find(flutter::EncodableValue("mouseXButton"));
            it != args->end()) {
          mouse = ReadUIntFromEncodable(it->second);
        }
      }
      InstallHooks(vk, mouse);
      result->Success(flutter::EncodableValue(g_keyboard_hook != nullptr ||
                                              g_mouse_hook != nullptr));
    } else if (call.method_name() == "clearPttHook") {
      ClearHooks();
      result->Success(flutter::EncodableValue(true));
    } else if (call.method_name() == "setPttEnabled") {
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      bool enabled = false;
      if (args) {
        if (const auto it = args->find(flutter::EncodableValue("enabled"));
            it != args->end()) {
          if (const auto* v = std::get_if<bool>(&it->second)) enabled = *v;
        }
      }
      g_ptt_enabled = enabled;
      result->Success(flutter::EncodableValue(true));
    } else {
      result->NotImplemented();
    }
  });
}

void UnregisterPttHooks() {
  ClearHooks();
  // The channel object itself is intentionally leaked (process-lifetime
  // singleton); the engine owns its messenger and is being torn down.
}

}  // namespace weconnect
