#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct CodexUsageView: View {
    let observation: CodexUsageObservation

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text("Codex capacity")
            .font(.subheadline.weight(.semibold))

          Spacer()

          Text(self.badgeText)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(self.observation.availability == .live ? .purple : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
              (self.observation.availability == .live ? Color.purple : Color.secondary)
                .opacity(0.12),
              in: Capsule()
            )
        }

        if let primary = self.observation.primary,
          self.observation.availability == .live
        {
          ProgressView(value: primary.remainingPercent, total: 100)
            .tint(.purple)

          HStack {
            Text(self.windowTitle(primary.windowDurationMinutes))
            Spacer()
            Text("Resets \(primary.resetsAt.formatted(date: .abbreviated, time: .shortened))")
          }
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)

          if let secondary = self.observation.secondary {
            Text(
              "\(self.windowTitle(secondary.windowDurationMinutes)): \(self.percent(secondary.remainingPercent)) remaining"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
          }
        } else {
          Text(self.observation.message ?? "Codex usage is unavailable.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Codex capacity")
      .accessibilityValue(self.accessibilityValue)
      .accessibilityHint("Read-only Codex quota usage and reset time reported by Codex.")
    }

    private var badgeText: String {
      guard self.observation.availability == .live, let primary = self.observation.primary else {
        return "UNAVAILABLE"
      }
      return "\(self.percent(primary.remainingPercent)) LEFT"
    }

    private var accessibilityValue: String {
      guard self.observation.availability == .live, let primary = self.observation.primary else {
        return self.observation.message ?? "Unavailable"
      }
      return
        "\(self.percent(primary.remainingPercent)) remaining in the \(self.windowTitle(primary.windowDurationMinutes).lowercased()), resets \(primary.resetsAt.formatted(date: .complete, time: .shortened))"
    }

    private func percent(_ value: Double) -> String {
      "\(Int(value.rounded()))%"
    }

    private func windowTitle(_ minutes: Int) -> String {
      switch minutes {
      case 300: "5-hour window"
      case 1_440: "Daily window"
      case 10_080: "Weekly window"
      case let value where value.isMultiple(of: 1_440): "\(value / 1_440)-day window"
      case let value where value.isMultiple(of: 60): "\(value / 60)-hour window"
      default: "\(minutes)-minute window"
      }
    }
  }
#endif
