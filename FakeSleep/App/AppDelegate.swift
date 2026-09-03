import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var container: AppContainer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    container = AppContainer()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    container?.prepareForTermination()
    return .terminateNow
  }
}
