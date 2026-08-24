#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct OxAuditView: View {
    let observation: OxAuditObservation

    var body: some View {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("OX FREE ISSUE SWEEP")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
              Text(self.observation.status?.state.title ?? "Status unavailable")
                .font(.callout.weight(.semibold))
            }
            Spacer()
            Text(self.badge)
              .font(.system(size: 9, weight: .bold, design: .rounded))
              .foregroundStyle(self.color)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(self.color.opacity(0.12), in: Capsule())
          }

          if let status = self.observation.status {
            ProgressView(
              value: Double(status.completedCount), total: Double(max(1, status.totalCount))
            )
            .tint(self.color)
            HStack(spacing: 8) {
              Text("\(status.completedCount)/\(status.totalCount) Issues")
              if let issue = status.currentIssue { Text("#\(issue)") }
              if let code = status.lastHTTPStatus { Text("HTTP \(code)") }
              Spacer()
              Text(self.timeText(status, now: context.date))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
          } else if let message = self.observation.message {
            Text(message).font(.caption2).foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
      }
    }

    private var badge: String {
      switch self.observation.availability {
      case .absent: "OFF"
      case .stale: "STALE"
      case .invalid: "INVALID"
      case .current: self.observation.status?.state.rawValue.uppercased() ?? "CURRENT"
      }
    }

    private var color: Color {
      guard self.observation.availability == .current, let state = self.observation.status?.state
      else {
        return self.observation.availability == .invalid ? .red : .orange
      }
      switch state {
      case .scanning, .available: return Color.purple
      case .completed: return Color.green
      case .backoff: return Color.orange
      case .stopped: return Color.secondary
      case .starting, .probing: return Color.blue
      }
    }

    private func timeText(_ status: OxAuditStatus, now: Date) -> String {
      if let next = status.nextAttemptAt {
        let seconds = max(0, Int(next.timeIntervalSince(now)))
        return "retry in \(seconds / 60)m \(seconds % 60)s"
      }
      return RelativeTimeFormatter.relativeDescription(from: status.updatedAt, to: now)
    }
  }
#endif
