#if os(macOS)
  import SwiftUI

  @main
  @MainActor
  struct MomentMonitorApp: App {
    @StateObject private var store: MonitorStore

    init() {
      let store = MonitorStore()
      self._store = StateObject(wrappedValue: store)
    }

    var body: some Scene {
      MenuBarExtra {
        MonitorMenuView()
          .environmentObject(self.store)
      } label: {
        Image(systemName: self.store.statusSymbol)
          .accessibilityLabel("Moment Monitor, \(self.store.statusAccessibilityValue)")
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
