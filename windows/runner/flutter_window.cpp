#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "pharmacy/window",
          &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // The channel uses the engine's messenger: release it before the engine.
  window_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Close button: ask Dart first, BEFORE the engine sees WM_CLOSE (see the
  // comment on window_channel_ in flutter_window.h for why).
  if (message == WM_CLOSE) {
    if (allow_close_) {
      ::DestroyWindow(hwnd);
      return 0;
    }
    if (window_channel_) {
      if (close_pending_) {
        return 0;
      }
      close_pending_ = true;
      // Dart did not answer (handler not registered yet, or failed): close
      // anyway. A till that cannot be closed is worse than a missed prompt.
      auto close_now = [this]() {
        close_pending_ = false;
        allow_close_ = true;
        ::PostMessage(GetHandle(), WM_CLOSE, 0, 0);
      };
      window_channel_->InvokeMethod(
          "closeRequested", nullptr,
          std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [this, close_now](const flutter::EncodableValue* result) {
                const bool exit =
                    result != nullptr &&
                    std::holds_alternative<std::string>(*result) &&
                    std::get<std::string>(*result) == "exit";
                if (exit) {
                  close_now();
                } else {
                  close_pending_ = false;  // user cancelled; window stays
                }
              },
              [close_now](const std::string&, const std::string&,
                          const flutter::EncodableValue*) { close_now(); },
              [close_now]() { close_now(); }));
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
