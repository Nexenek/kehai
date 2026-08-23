#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "presence_channel.h"
#include "transparency_channel.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Now-playing/idle MethodChannel backing WindowsPresenceService. Created
  // once the engine's messenger exists, torn down with everything else in
  // OnDestroy.
  std::unique_ptr<PresenceChannel> presence_channel_;

  // The mini-transparency MethodChannel backing
  // DesktopWindowService.setMiniTransparency. Same lifetime as
  // presence_channel_.
  std::unique_ptr<TransparencyChannel> transparency_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
