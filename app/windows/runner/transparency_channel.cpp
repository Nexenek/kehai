#include "transparency_channel.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <utility>

using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

// The "sheet of glass" trick: extending the frame across the entire client
// area (all four margins -1) tells DWM this whole window is compositable
// glass, so the alpha the Flutter engine already renders (it clears to
// (0,0,0,0) every frame) shows the desktop through instead of being treated
// as opaque black. Zero margins is DWM's ordinary default — a normal, fully
// opaque window — which is what restores the expanded panel's look.
bool ApplyGlassSheet(HWND hwnd, bool enable) {
  if (hwnd == nullptr) return false;
  MARGINS margins = {0, 0, 0, 0};
  if (enable) {
    margins = {-1, -1, -1, -1};
  }
  return SUCCEEDED(DwmExtendFrameIntoClientArea(hwnd, &margins));
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
    const bool applied = ApplyGlassSheet(hwnd, *enable);
    // Turning transparency off is a best-effort restore either way — the
    // window is opaque by DWM's own default even if this particular call
    // failed, so there's nothing useful to report back as "capability" for
    // that direction; only the "turn it on" answer feeds
    // DesktopWindowService.wantsTransparentMini.
    result->Success(EncodableValue(*enable ? applied : true));
  } catch (...) {
    // Never let a DWM hiccup take the window down with it.
    result->Success(EncodableValue(false));
  }
}
