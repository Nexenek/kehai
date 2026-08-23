#ifndef RUNNER_PRESENCE_CHANNEL_H_
#define RUNNER_PRESENCE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Owns the `app.kehai/presence` MethodChannel used by WindowsPresenceService
// (lib/data/services/presence/windows_presence_service.dart) to read
// now-playing media via GlobalSystemMediaTransportControlsSessionManager
// (WinRT) and idle time via GetLastInputInfo — see kb/platform-desktop.md's
// "Now-playing" / "Idle / presence" tables.
//
// `getNowPlaying` does its WinRT work (including the blocking `.get()` on
// the async media-properties call) on a background thread so it never
// stalls the platform thread; `getIdleSeconds` is answered synchronously
// since GetLastInputInfo is cheap. Both degrade to a clean "nothing" result
// (null / 0) rather than throwing when there's no session or the call
// fails — this must never crash the app.
class PresenceChannel {
 public:
  // |messenger| is owned by the engine, which outlives the FlutterWindow
  // that constructs this channel.
  explicit PresenceChannel(flutter::BinaryMessenger* messenger);
  ~PresenceChannel();

  PresenceChannel(const PresenceChannel&) = delete;
  PresenceChannel& operator=(const PresenceChannel&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_PRESENCE_CHANNEL_H_
