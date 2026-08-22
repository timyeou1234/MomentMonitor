#if os(macOS)
  import SwiftUI

  @main
  @MainActor
  struct MomentMonitorApp: App {
    @StateObject private var store = MonitorStore()

    var body: some Scene {
      MenuBarExtra {
        MonitorMenuView()
          .environmentObject(self.store)
      } label: {
        Image(systemName: self.store.statusSymbol)
          .accessibilityLabel("Moment Monitor")
      }
      .menuBarExtraStyle(.window)

      Settings {
        MonitorSettingsView()
          .environmentObject(self.store)
      }
    }
  }
#else
  import Foundation

  @main
  enum MomentMonitorUnsupportedPlatform {
    static func main() {
      print(
        "MomentMonitor’s menu-bar UI is available on macOS. The core library and tests are cross-platform."
      )
    }
  }
#endif
