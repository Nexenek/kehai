#include "transparency_channel.h"

#include <flutter/standard_method_codec.h>

#include <utility>

using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

// SetWindowCompositionAttribute is an undocumented user32.dll export — no
// Windows SDK header declares it, so the handful of structs/enums it needs
// are reproduced here from the well-established reverse-engineered layout
// used by flutter_acrylic and similar Windows Fluent-Design shell tweaks.
enum AccentState : DWORD {
  kAccentDisabled = 0,
  kAccentEnableTransparentGradient = 2,
};

struct AccentPolicy {
  DWORD accent_state;
  DWORD accent_flags;
  DWORD gradient_color;  // 0xAABBGGRR; only the alpha byte matters below.
  DWORD animation_id;
};

enum WindowCompositionAttrib : DWORD {
  kWcaAccentPolicy = 19,
};

struct WindowCompositionAttribData {
  DWORD attrib;
  PVOID data;
  SIZE_T size_of_data;
};

using SetWindowCompositionAttributeFn =
    BOOL(WINAPI*)(HWND, WindowCompositionAttribData*);

// Resolved once and cached: GetProcAddress on a system DLL that's already
// loaded (user32.dll always is) is cheap, but there's no reason to repeat it
// on every setTransparent(true/false) toggle between mini and expanded.
SetWindowCompositionAttributeFn ResolveSetWindowCompositionAttribute() {
  static SetWindowCompositionAttributeFn cached = []() {
    HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
    return user32 == nullptr
               ? SetWindowCompositionAttributeFn(nullptr)
               : reinterpret_cast<SetWindowCompositionAttributeFn>(
                     ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  }();
  return cached;
}

// Turns the see-through accent on or off. Zero-alpha gradient colour means
// no tint — DWM just composites the window straight against the desktop
// wherever the app itself draws nothing, which is exactly the mini card's
// dropped-fill look (MiniPartnerWindow / mini_partner_window.dart).
// Disabling goes back to AccentDisabled, DWM's ordinary opaque compositing —
// what the expanded panel wants.
bool ApplyTransparentAccent(HWND hwnd, bool enable) {
  if (hwnd == nullptr) return false;
  auto set_composition_attribute = ResolveSetWindowCompositionAttribute();
  if (set_composition_attribute == nullptr) return false;

  AccentPolicy policy{};
  policy.accent_state =
      enable ? kAccentEnableTransparentGradient : kAccentDisabled;
  policy.gradient_color = 0x00000000;

  WindowCompositionAttribData data{};
  data.attrib = kWcaAccentPolicy;
  data.data = &policy;
  data.size_of_data = sizeof(policy);

  return set_composition_attribute(hwnd, &data) != FALSE;
}

}  // namespace

TransparencyChannel::TransparencyChannel(
    flutter::BinaryMessenger* messenger,
    std::function<HWND()> get_top_level_window)
    : get_top_level_window_(std::move(get_top_level_window)) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "app.kehai/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

TransparencyChannel::~TransparencyChannel() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void TransparencyChannel::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (call.method_name() != "setTransparent") {
    result->NotImplemented();
    return;
  }

  const auto* enable = std::get_if<bool>(call.arguments());
  if (enable == nullptr) {
    result->Error("bad_arguments", "setTransparent wants a bool");
    return;
  }

  try {
    HWND hwnd = get_top_level_window_ ? get_top_level_window_() : nullptr;
    const bool applied = ApplyTransparentAccent(hwnd, *enable);
    // Turning transparency off is a best-effort restore either way — the
    // window is opaque by DWM's own default even if this particular call
    // failed, so there's nothing useful to report back as "capability" for
    // that direction; only the "turn it on" answer feeds
    // DesktopWindowService.wantsTransparentMini.
    result->Success(EncodableValue(*enable ? applied : true));
  } catch (...) {
    // Never let an undocumented-API hiccup take the window down with it.
    result->Success(EncodableValue(false));
  }
}
