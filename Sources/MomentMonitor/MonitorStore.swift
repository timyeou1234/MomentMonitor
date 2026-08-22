#if os(macOS)
  import AppKit
  import Foundation
  import MomentMonitorCore
  import SwiftUI

  @MainActor
  final class MonitorStore: ObservableObject {
    @Published private(set) var snapshot: MomentMonitorSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published var repositoryText: String
    @Published var refreshIntervalSeconds: Int
    @Published var completedItemLimit: Int

    private var service: MomentMonitorService?
    private var pollingTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
      self.defaults = defaults
      self.repositoryText =
        defaults.string(forKey: "repository") ?? RepositoryCoordinate.moment.fullName
      self.refreshIntervalSeconds = defaults.object(forKey: "refreshIntervalSeconds") as? Int ?? 30
      self.completedItemLimit = defaults.object(forKey: "completedItemLimit") as? Int ?? 8
      self.snapshot = .empty(repository: .moment)

      self.restartPolling()
      Task { await self.refresh() }
    }

    var statusSymbol: String {
      if self.lastError != nil || self.snapshot.health == .attention {
        return "exclamationmark.triangle.fill"
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

    var lastUpdatedText: String {
      RelativeTimeFormatter.relativeDescription(from: self.snapshot.generatedAt)
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
          try await created.verifyPrerequisites()
          self.service = created
          service = created
        }

        let refreshed = try await service.refresh(configuration: configuration)
        self.snapshot = refreshed
        self.lastError = nil
      } catch {
        self.lastError = error.localizedDescription
      }
    }

    func applyPreferences() {
      self.refreshIntervalSeconds = min(max(15, self.refreshIntervalSeconds), 300)
      self.completedItemLimit = min(max(1, self.completedItemLimit), 30)
      self.defaults.set(self.repositoryText, forKey: "repository")
      self.defaults.set(self.refreshIntervalSeconds, forKey: "refreshIntervalSeconds")
      self.defaults.set(self.completedItemLimit, forKey: "completedItemLimit")
      self.restartPolling()
      Task { await self.refresh() }
    }

    func openRepository() {
      guard let coordinate = try? RepositoryCoordinate(parsing: self.repositoryText),
        let url = URL(string: "https://github.com/\(coordinate.fullName)")
      else { return }
      NSWorkspace.shared.open(url)
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
  }
#endif
