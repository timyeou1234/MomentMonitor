#if os(macOS)
  import AppKit
  import MomentMonitorCore
  import SwiftUI

  struct MonitorMenuView: View {
    @EnvironmentObject private var store: MonitorStore
    @Environment(\.openSettings) private var openSettings

    private let laneOrder: [MonitorLane] = [
      .blocked,
      .running,
      .queued,
      .prChecks,
      .ready,
      .waiting,
      .completed,
    ]

    var body: some View {
      VStack(spacing: 0) {
        self.header
        Divider()

        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            if let error = self.store.lastError {
              ErrorBanner(message: error)
            }

            if self.store.isRefreshing, self.store.snapshot.items.isEmpty {
              HStack {
                Spacer()
                ProgressView("Reading GitHub…")
                  .controlSize(.small)
                Spacer()
              }
              .padding(.vertical, 24)
            } else if self.store.snapshot.items.isEmpty, self.store.lastError == nil {
              self.idleState
            }

            ForEach(self.laneOrder, id: \.self) { lane in
              let items = self.store.snapshot.items(in: lane)
              if !items.isEmpty {
                MonitorSectionView(lane: lane, items: items)
              }
            }
          }
          .padding(14)
        }
        .frame(width: 440, height: 590)

        Divider()
        self.footer
      }
      .background(.regularMaterial)
      .task {
        if self.store.snapshot.items.isEmpty {
          await self.store.refresh()
        }
      }
    }

    private var header: some View {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Moments Automation")
            .font(.headline)
          Text(self.store.repositoryText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text("READ ONLY")
          .font(.caption2.weight(.semibold))
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(.green.opacity(0.14), in: Capsule())
          .foregroundStyle(.green)

        Button {
          Task { await self.store.refresh() }
        } label: {
          if self.store.isRefreshing {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: "arrow.clockwise")
          }
        }
        .buttonStyle(.borderless)
        .help("Refresh")
        .disabled(self.store.isRefreshing)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
    }

    private var footer: some View {
      HStack {
        Text("Updated \(self.store.lastUpdatedText)")
          .font(.caption2)
          .foregroundStyle(.secondary)

        Spacer()

        Button("GitHub") {
          self.store.openRepository()
        }
        .buttonStyle(.borderless)

        Button("Settings") {
          self.openSettings()
        }
        .buttonStyle(.borderless)

        Button("Quit") {
          NSApp.terminate(nil)
        }
        .buttonStyle(.borderless)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }

    private var idleState: some View {
      VStack(spacing: 8) {
        Image(systemName: "checkmark.circle")
          .font(.system(size: 30))
          .foregroundStyle(.green)
        Text("Automation is idle")
          .font(.headline)
        Text(
          "No queued, running, open automation PR, blocked, or recently completed work was found."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 310)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 36)
    }
  }

  private struct ErrorBanner: View {
    let message: String

    var body: some View {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(self.message)
          .font(.caption)
          .textSelection(.enabled)
        Spacer(minLength: 0)
      }
      .padding(10)
      .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }
  }
#endif
