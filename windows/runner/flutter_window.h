#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

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

  // Channel "pharmacy/window": the close button is routed to Dart through it.
  //
  // The engine forwards WM_CLOSE to the framework (didRequestAppExit) ONLY
  // when this is the last top-level window of the process. Any hidden
  // top-level window created in-process (e.g. by an RDP-redirected printer
  // driver after the first receipt print) makes the engine let the window
  // close silently, and the "close shift / Z-report" dialog never shows.
  // Observed 2026-09-10. So the runner intercepts WM_CLOSE itself.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Set once Dart answered "exit" (or could not answer): the next WM_CLOSE
  // really closes the window.
  bool allow_close_ = false;

  // A close request is already waiting for Dart; ignore repeated clicks.
  bool close_pending_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
