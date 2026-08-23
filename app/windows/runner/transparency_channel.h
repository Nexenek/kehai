#ifndef RUNNER_TRANSPARENCY_CHANNEL_H_
#define RUNNER_TRANSPARENCY_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <functional>
#include <memory>

// Owns the `app.kehai/window` MethodChannel used by
// DesktopWindowService.setMiniTransparency
// (lib/data/services/desktop_window_service.dart) to ask for genuine
// per-pixel window transparency around the mini partner card, and to
// restore an opaque window for the full panel.
//
// The technique is DWM's classic "sheet of glass": the Flutter engine's
// Windows compositor already clears every frame to (0,0,0,0)
// (compositor_opengl.cc) and renders through an EGL surface with an alpha
// channel, so nothing on the Dart/engine side needs to change — the window
// itself just needs DWM to treat its client area as compositable instead of
// opaque. `DwmExtendFrameIntoClientArea` with all margins set to -1 does
// exactly that; margins of 0 (the default) hands DWM back its normal
// opaque-window behaviour. No WS_EX_LAYERED is used — that model is for
// GDI-rendered layered windows updated via UpdateLayeredWindow, and fighting
// it against the engine's own Direct3D/ANGLE swap chain is the mistake a
// previous pass here correctly avoided.
//
// `setTransparent` replies with whether transparency is actually active
// afterward: DWM composition has been mandatory-on since Windows 8, so in
// practice this succeeds whenever the call reaches a live top-level window,
// and reports false only if there's no window yet or the DWM call itself
// fails — never throws, matching every other native channel in this app.
class TransparencyChannel {
 public:
  // |messenger| is owned by the engine, which outlives the FlutterWindow
  // that constructs this channel. |top_level_window| is queried lazily via
  // the callback on every call, since it's stable for the app's whole life
  // but this keeps the channel from caring about construction order.
  TransparencyChannel(flutter::BinaryMessenger* messenger,
                      std::function<HWND()> get_top_level_window);
  ~TransparencyChannel();

  TransparencyChannel(const TransparencyChannel&) = delete;
  TransparencyChannel& operator=(const TransparencyChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::function<HWND()> get_top_level_window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_TRANSPARENCY_CHANNEL_H_
