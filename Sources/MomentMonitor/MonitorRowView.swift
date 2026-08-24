#if os(macOS)
  import AppKit
  import MomentMonitorCore
  import SwiftUI

  struct MonitorRowView: View {
    let item: MonitorItem

    var body: some View {
      Button {
        NSWorkspace.shared.open(self.item.url)
      } label: {
        HStack(alignment: .top, spacing: 9) {
          Image(systemName: self.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(self.symbolColor)
            .frame(width: 18, height: 18)
            .padding(.top, 1)

          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(self.item.title)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.primary)

              Spacer(minLength: 4)

              if let status = self.item.statusText {
                Text(status.uppercased())
                  .font(.system(size: 9, weight: .semibold, design: .rounded))
                  .foregroundStyle(self.statusColor)
                  .padding(.horizontal, 5)
                  .padding(.vertical, 2)
                  .background(self.statusColor.opacity(0.10), in: Capsule())
                  .lineLimit(1)
              }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(self.item.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

              Spacer(minLength: 4)

              if let duration = self.item.automationDurationMilliseconds {
                Text("Codex \(RelativeTimeFormatter.compactDuration(milliseconds: duration))")
                  .font(.caption2.monospacedDigit().weight(.medium))
                  .foregroundStyle(self.statusColor)
                  .lineLimit(1)
                  .accessibilityLabel(
                    "Recorded Codex time \(RelativeTimeFormatter.compactDuration(milliseconds: duration))"
                  )
              }

              Text(RelativeTimeFormatter.relativeDescription(from: self.item.updatedAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
      }
      .buttonStyle(.plain)
    }

    private var symbolName: String {
      switch self.item.lane {
      case .ready: "tray.and.arrow.down"
      case .waiting: "link"
      case .queued: "hourglass"
      case .running: "arrow.triangle.2.circlepath"
      case .prChecks: "arrow.triangle.merge"
      case .blocked: "exclamationmark.octagon.fill"
      case .completed: "checkmark.circle.fill"
      }
    }

    private var symbolColor: Color {
      switch self.item.lane {
      case .ready: .green
      case .waiting: .secondary
      case .queued: .orange
      case .running: .blue
      case .prChecks: .purple
      case .blocked: .red
      case .completed: .green
      }
    }

    private var statusColor: Color {
      switch self.item.severity {
      case .normal: .secondary
      case .active: .blue
      case .warning: .red
      case .success: .green
      }
    }
  }
#endif
