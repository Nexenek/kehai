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
// The textbook DWM "sheet of glass" trick (DwmExtendFrameIntoClientArea with
// all margins -1) was tried first — the Flutter engine's Windows compositor
// already clears every frame to (0,0,0,0) (compositor_opengl.cc) through an
// EGL surface with an alpha channel, so nothing on the Dart/engine side
// needed to change for it. It reported success (S_OK) but did not actually
// show through on a real machine: measured with a live build, the mini card
// kept rendering its opaque fallback. That trick is written for a window
// whose own GDI-redirected bitmap carries the alpha; Flutter's child window
// presents through a hardware (ANGLE/Direct3D11) swap chain, which this
// class's DWM redirection surface doesn't compose the same way.
//
// What does work — and is the technique flutter_acrylic (a widely used
// Flutter Windows transparency/acrylic plugin) itself relies on —
// is the undocumented `SetWindowCompositionAttribute` user32 export with an
// `ACCENT_ENABLE_TRANSPARENTGRADIENT` policy and a zero-alpha gradient
// colour: it asks DWM to composite the *whole* window against the desktop
// directly, rather than relying on the app's own redirection-surface alpha,
// which is what actually shows through a D3D-backed child surface. No
// WS_EX_LAYERED is used either way — that model is for GDI-rendered layered
// windows updated via UpdateLayeredWindow, and fighting it against the
// engine's own swap chain was the mistake a previous pass here correctly
// avoided.
//
// `setTransparent` replies with whether transparency is actually active
// afterward: false whenever there's no window yet, the undocumented export
// isn't present on this Windows build (SetWindowCompositionAttribute has
// existed since Windows 10 1809's public surface but was never a documented,
// guaranteed API), or the call itself fails — never throws, matching every
// other native channel in this app.
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
