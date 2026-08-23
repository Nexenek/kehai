#include "presence_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>

#include <algorithm>
#include <cwctype>
#include <memory>
#include <optional>
#include <string>
#include <thread>

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionManager;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionPlaybackStatus;

// Null-terminated wide string -> UTF-8 std::string. Empty/null input maps
// to an empty result rather than erroring — plenty of sessions leave e.g.
// AlbumTitle blank, and a window can legitimately have no title.
std::string WideToUtf8(const wchar_t* wide) {
  if (wide == nullptr || *wide == L'\0') return {};
  int size =
      ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(static_cast<size_t>(size) - 1, '\0');  // drop the NUL
  ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, result.data(), size, nullptr,
                        nullptr);
  return result;
}

std::string ToUtf8(const winrt::hstring& value) {
  return value.empty() ? std::string() : WideToUtf8(value.c_str());
}

EncodableValue OptionalString(const std::string& value) {
  return value.empty() ? EncodableValue() : EncodableValue(value);
}

// Runs the actual GSMTC lookup. Must be called off the platform thread: the
// media-properties fetch is async-over-sync (`.get()`), and GSMTC itself is
// COM/WinRT plumbing that can stall briefly talking to whatever app owns
// the current session.
//
// Mirrors LinuxPresenceService/MprisMapper's "no usable now-playing" cases:
// no session, a status that isn't Playing/Paused, or no title all map to
// std::nullopt (-> a null result to Dart), never a thrown/propagated error.
std::optional<EncodableMap> ReadNowPlaying() {
  try {
    auto manager =
        GlobalSystemMediaTransportControlsSessionManager::RequestAsync()
            .get();
    auto session = manager.GetCurrentSession();
    if (session == nullptr) return std::nullopt;

    const char* state = nullptr;
    switch (session.GetPlaybackInfo().PlaybackStatus()) {
      case GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing:
        state = "playing";
        break;
      case GlobalSystemMediaTransportControlsSessionPlaybackStatus::Paused:
        state = "paused";
        break;
      default:
        // Stopped/Closed/Changing/Opened - nothing worth surfacing.
        return std::nullopt;
    }

    auto props = session.TryGetMediaPropertiesAsync().get();
    std::string title = ToUtf8(props.Title());
    if (title.empty()) return std::nullopt;

    EncodableMap result;
    result[EncodableValue("title")] = EncodableValue(title);
    result[EncodableValue("artist")] = OptionalString(ToUtf8(props.Artist()));
    result[EncodableValue("album")] =
        OptionalString(ToUtf8(props.AlbumTitle()));
    // Raw AUMID (e.g. "Spotify.exe", a browser's package family name) -
    // WindowsPresenceService/WindowsPlayerMapper on the Dart side prettifies
    // this into a short label, kept there so it's unit-testable without a
    // real channel.
    result[EncodableValue("player")] =
        OptionalString(ToUtf8(session.SourceAppUserModelId()));
    result[EncodableValue("state")] = EncodableValue(std::string(state));
    return result;
  } catch (...) {
    // No session manager on this Windows build, a call failed, or the
    // session vanished mid-read - degrade to "nothing playing".
    return std::nullopt;
  }
}

int64_t ReadIdleSeconds() {
  LASTINPUTINFO info{};
  info.cbSize = sizeof(LASTINPUTINFO);
  if (!::GetLastInputInfo(&info)) return 0;
  const DWORD now = ::GetTickCount();
  const DWORD idle_ms = now >= info.dwTime ? now - info.dwTime : 0;
  return static_cast<int64_t>(idle_ms / 1000);
}

std::wstring BaseName(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

std::wstring StripExeExtension(const std::wstring& name) {
  static const std::wstring kExt = L".exe";
  if (name.size() >= kExt.size() &&
      ::_wcsicmp(name.c_str() + (name.size() - kExt.size()), kExt.c_str()) ==
          0) {
    return name.substr(0, name.size() - kExt.size());
  }
  return name;
}

// Plain Win32, answered synchronously on the platform thread (all of these
// calls are cheap — no async/background thread needed, unlike GSMTC above).
//
// Returns std::nullopt for "nothing to report": no foreground window, or a
// process we can't query (most commonly an elevated process our
// non-elevated app isn't allowed to open — PROCESS_QUERY_LIMITED_INFORMATION
// still fails for those; this is expected, not an error worth surfacing).
std::optional<EncodableMap> ReadForegroundApp() {
  try {
    HWND hwnd = ::GetForegroundWindow();
    if (hwnd == nullptr) return std::nullopt;

    DWORD pid = 0;
    ::GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0) return std::nullopt;

    HANDLE process =
        ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (process == nullptr) return std::nullopt;  // access denied, e.g. elevated

    wchar_t path_buffer[MAX_PATH];
    DWORD path_size = MAX_PATH;
    BOOL ok = ::QueryFullProcessImageNameW(process, 0, path_buffer, &path_size);
    ::CloseHandle(process);
    if (!ok || path_size == 0) return std::nullopt;

    std::wstring exe_name =
        StripExeExtension(BaseName(std::wstring(path_buffer, path_size)));
    std::transform(exe_name.begin(), exe_name.end(), exe_name.begin(),
                   [](wchar_t c) { return ::towlower(c); });
    std::string exe_utf8 = WideToUtf8(exe_name.c_str());
    if (exe_utf8.empty()) return std::nullopt;

    std::wstring title;
    const int title_len = ::GetWindowTextLengthW(hwnd);
    if (title_len > 0) {
      title.resize(static_cast<size_t>(title_len) + 1);
      const int copied = ::GetWindowTextW(hwnd, title.data(), title_len + 1);
      title.resize(copied > 0 ? static_cast<size_t>(copied) : 0);
    }

    EncodableMap result;
    result[EncodableValue("exe")] = EncodableValue(exe_utf8);
    result[EncodableValue("title")] = EncodableValue(WideToUtf8(title.c_str()));
    return result;
  } catch (...) {
    // Never let a foreground-window read take the app down.
    return std::nullopt;
  }
}

}  // namespace

PresenceChannel::PresenceChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "app.kehai/presence",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        HandleMethodCall(call, std::move(result));
      });
}

PresenceChannel::~PresenceChannel() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}

void PresenceChannel::HandleMethodCall(
    const MethodCall<EncodableValue>& call,
    std::unique_ptr<MethodResult<EncodableValue>> result) {
  if (call.method_name() == "getNowPlaying") {
    // MethodResult isn't copyable, so hand it to the background thread via
    // a shared_ptr (the flutter Windows embedder's reply plumbing is safe
    // to invoke from any thread - this is the standard pattern for
    // async-native-work plugins).
    std::shared_ptr<MethodResult<EncodableValue>> shared_result(
        std::move(result));
    std::thread([shared_result]() {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      auto now_playing = ReadNowPlaying();
      if (now_playing.has_value()) {
        shared_result->Success(EncodableValue(*now_playing));
      } else {
        shared_result->Success();
      }
      winrt::uninit_apartment();
    }).detach();
  } else if (call.method_name() == "getIdleSeconds") {
    result->Success(EncodableValue(ReadIdleSeconds()));
  } else if (call.method_name() == "getForegroundApp") {
    auto foreground = ReadForegroundApp();
    if (foreground.has_value()) {
      result->Success(EncodableValue(*foreground));
    } else {
      result->Success();
    }
  } else {
    result->NotImplemented();
  }
}
