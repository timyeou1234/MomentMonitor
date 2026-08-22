#if os(macOS)
  import AppKit
  import Foundation
  import MomentMonitorCore
  import OSLog
  import SwiftUI

  @MainActor
  final class MonitorStore: ObservableObject {
    private static let logger = Logger(
      subsystem: "com.timyeou.momentmonitor",
      category: "MobileDashboard"
    )
    @Published private(set) var snapshot: MomentMonitorSnapshot {
      didSet { self.mobileDashboardSnapshotStore.update(self.snapshot) }
    }
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var hasSuccessfulRefresh = false
    @Published private(set) var settingsFeedback: String?
    @Published private(set) var settingsFeedbackIsError = false
    @Published var repositoryText: String
    @Published var refreshIntervalSeconds: Int
    @Published var completedItemLimit: Int
    @Published var mobileDashboardEnabled: Bool
    @Published var mobileDashboardPort: Int
    @Published private(set) var mobileDashboardState: MobileDashboardServerState = .stopped

    private var service: MomentMonitorService?
    private var pollingTask: Task<Void, Never>?
    private var runtimePollingTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let mobileDashboardSnapshotStore: MobileDashboardSnapshotStore
    private lazy var mobileDashboardServer: MobileDashboardServer? = {
      do {
        return try MobileDashboardServer(snapshotStore: self.mobileDashboardSnapshotStore) {
          [weak self] state in
          Task { @MainActor [weak self] in
            self?.mobileDashboardState = state
            Self.logger.info("Mobile dashboard state changed to \(String(describing: state))")
          }
        }
      } catch {
        self.mobileDashboardState = .failed(message: error.localizedDescription)
        return nil
      }
    }()

    init(defaults: UserDefaults = .standard) {
      self.defaults = defaults
      self.repositoryText =
        defaults.string(forKey: "repository") ?? RepositoryCoordinate.moment.fullName
      self.refreshIntervalSeconds = defaults.object(forKey: "refreshIntervalSeconds") as? Int ?? 30
      self.completedItemLimit = defaults.object(forKey: "completedItemLimit") as? Int ?? 8
      self.mobileDashboardEnabled = defaults.bool(forKey: "mobileDashboardEnabled")
      self.mobileDashboardPort =
        defaults.object(forKey: "mobileDashboardPort") as? Int
        ?? MobileDashboardServer.defaultPort
      let initialSnapshot = MomentMonitorSnapshot.empty(repository: .moment)
      self.snapshot = initialSnapshot
      self.mobileDashboardSnapshotStore = MobileDashboardSnapshotStore(snapshot: initialSnapshot)

      Self.logger.info(
        "Mobile dashboard preference is \(self.mobileDashboardEnabled, privacy: .public) on port \(self.mobileDashboardPort, privacy: .public)"
      )

      self.restartPolling()
      self.startRuntimePolling()
      self.restartMobileDashboard()
      Task { await self.refresh() }
    }

    var statusSymbol: String {
      if self.lastError != nil || self.snapshot.health == .attention {
        return "exclamationmark.triangle.fill"
      }
      if !self.hasSuccessfulRefresh {
        return self.isRefreshing ? "arrow.triangle.2.circlepath" : "ellipsis.circle"
      }
      switch self.snapshot.health {
      case .busy:
        return "arrow.triangle.2.circlepath"
      case .idle:
        return "checkmark.circle"
      case .attention:
        return "exclamationmark.triangle.fill"
      }
    }

    var statusAccessibilityValue: String {
      if self.lastError != nil {
        return "Refresh failed"
      }
      if !self.hasSuccessfulRefresh {
        return self.isRefreshing ? "Refreshing" : "Not updated yet"
      }
      switch self.snapshot.health {
      case .attention:
        return "Attention required"
      case .busy:
        return "\(self.snapshot.activeCount) active items"
      case .idle:
        return "Idle"
      }
    }

    var updateStatusText: String {
      guard self.hasSuccessfulRefresh else { return "Not updated yet" }
      return "Updated \(RelativeTimeFormatter.relativeDescription(from: self.snapshot.generatedAt))"
    }

    var repositoryValidationMessage: String? {
      do {
        _ = try RepositoryCoordinate(parsing: self.repositoryText)
        return nil
      } catch {
        return error.localizedDescription
      }
    }

    var mobileDashboardValidationMessage: String? {
      (1_024...65_535).contains(self.mobileDashboardPort)
        ? nil : "Choose a port between 1024 and 65535."
    }

    var mobileDashboardStatusText: String {
      switch self.mobileDashboardState {
      case .stopped: self.mobileDashboardEnabled ? "Stopped" : "Off"
      case .starting: "Starting on this Mac…"
      case .ready(let port): "Ready at http://127.0.0.1:\(port)"
      case .failed(let message): "Could not start: \(message)"
      }
    }

    var mobileDashboardStatusIsError: Bool {
      if case .failed = self.mobileDashboardState { return true }
      return false
    }

    var mobileDashboardLocalURL: URL? {
      guard case .ready(let port) = self.mobileDashboardState else { return nil }
      return URL(string: "http://127.0.0.1:\(port)")
    }

    var tailscaleServeCommand: String {
      "tailscale serve --bg http://127.0.0.1:\(self.mobileDashboardPort)"
    }

    func refresh() async {
      guard !self.isRefreshing else { return }
      self.isRefreshing = true
      defer { self.isRefreshing = false }

      do {
        let configuration = try self.configuration()
        let service: MomentMonitorService
        if let existing = self.service {
          service = existing
        } else {
          let created = try MomentMonitorService.live()
          self.service = created
          try await created.verifyPrerequisites()
          service = created
        }

        let refreshed = try await service.refresh(configuration: configuration)
        self.snapshot = refreshed
        self.hasSuccessfulRefresh = true
        self.lastError = nil
      } catch {
        if let service = self.service, let configuration = try? self.configuration() {
          let runtimeObservation = await service.readRuntimeStatus(configuration: configuration)
          self.snapshot = self.snapshot.replacingRuntimeObservation(runtimeObservation)
        }
        self.lastError = error.localizedDescription
      }
    }

    func applyPreferences() async {
      let configuration: MonitorConfiguration
      do {
        configuration = try self.configuration()
      } catch {
        self.settingsFeedback = error.localizedDescription
        self.settingsFeedbackIsError = true
        return
      }

      self.repositoryText = configuration.repository.fullName
      self.refreshIntervalSeconds = min(max(15, self.refreshIntervalSeconds), 300)
      self.completedItemLimit = min(max(1, self.completedItemLimit), 30)
      guard self.mobileDashboardValidationMessage == nil else {
        self.settingsFeedback = self.mobileDashboardValidationMessage
        self.settingsFeedbackIsError = true
        return
      }
      self.defaults.set(self.repositoryText, forKey: "repository")
      self.defaults.set(self.refreshIntervalSeconds, forKey: "refreshIntervalSeconds")
      self.defaults.set(self.completedItemLimit, forKey: "completedItemLimit")
      self.defaults.set(self.mobileDashboardEnabled, forKey: "mobileDashboardEnabled")
      self.defaults.set(self.mobileDashboardPort, forKey: "mobileDashboardPort")
      self.restartPolling()
      self.restartMobileDashboard()
      await self.refresh()
      if let lastError = self.lastError {
        self.settingsFeedback = "Saved, but refresh failed: \(lastError)"
        self.settingsFeedbackIsError = true
      } else {
        self.settingsFeedback = "Saved and refreshed."
        self.settingsFeedbackIsError = false
      }
    }

    func clearSettingsFeedback() {
      self.settingsFeedback = nil
      self.settingsFeedbackIsError = false
    }

    func openRepository() {
      guard let coordinate = try? RepositoryCoordinate(parsing: self.repositoryText),
        let url = URL(string: "https://github.com/\(coordinate.fullName)")
      else { return }
      NSWorkspace.shared.open(url)
    }

    func openMobileDashboard() {
      guard let url = self.mobileDashboardLocalURL else { return }
      NSWorkspace.shared.open(url)
    }

    func copyTailscaleCommand() {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(self.tailscaleServeCommand, forType: .string)
      self.settingsFeedback = "Copied the private Tailscale Serve command."
      self.settingsFeedbackIsError = false
    }

    private func configuration() throws -> MonitorConfiguration {
      MonitorConfiguration(
        repository: try RepositoryCoordinate(parsing: self.repositoryText),
        refreshIntervalSeconds: TimeInterval(self.refreshIntervalSeconds),
        completedItemLimit: self.completedItemLimit
      )
    }

    private func restartPolling() {
      self.pollingTask?.cancel()
      let interval = UInt64(max(15, self.refreshIntervalSeconds)) * 1_000_000_000
      self.pollingTask = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: interval)
          guard let self, !Task.isCancelled else { return }
          await self.refresh()
        }
      }
    }

    private func startRuntimePolling() {
      self.runtimePollingTask?.cancel()
      self.runtimePollingTask = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 1_000_000_000)
          guard let self else { return }
          guard !Task.isCancelled, let service = self.service,
            let configuration = try? self.configuration()
          else { continue }
          let observation = await service.readRuntimeStatus(configuration: configuration)
          if observation != self.snapshot.runtimeObservation {
            self.snapshot = self.snapshot.replacingRuntimeObservation(observation)
          }
        }
      }
    }

    private func restartMobileDashboard() {
      guard self.mobileDashboardEnabled else {
        self.mobileDashboardServer?.stop()
        self.mobileDashboardState = .stopped
        return
      }
      guard self.mobileDashboardValidationMessage == nil,
        let server = self.mobileDashboardServer
      else { return }
      do {
        try server.start(port: self.mobileDashboardPort)
      } catch {
        Self.logger.error("Mobile dashboard failed to start: \(error.localizedDescription)")
        self.mobileDashboardState = .failed(message: error.localizedDescription)
      }
    }
  }
#endif
