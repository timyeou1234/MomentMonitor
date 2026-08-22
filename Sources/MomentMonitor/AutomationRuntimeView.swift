#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct AutomationRuntimeView: View {
    let observation: AutomationRuntimeObservation

    var body: some View {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        VStack(alignment: .leading, spacing: 9) {
          HStack(spacing: 8) {
            Text(self.sectionTitle)
              .font(.subheadline.weight(.semibold))

            Spacer()

            Text(self.badgeText)
              .font(.system(size: 9, weight: .bold, design: .rounded))
              .foregroundStyle(self.accentColor)
              .padding(.horizontal, 6)
              .padding(.vertical, 3)
              .background(self.accentColor.opacity(0.12), in: Capsule())
          }

          if let status = self.observation.status {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
              Image(systemName: self.symbolName)
                .foregroundStyle(self.accentColor)
              Text(self.phaseTitle(status))
                .font(.callout.weight(.semibold))
              Spacer(minLength: 4)
              Text(self.phaseTime(status, now: context.date))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }

            self.stageTrack(status)

            HStack(spacing: 7) {
              Text("Issue #\(status.issueNumber)")
              if let pullRequestNumber = status.pullRequestNumber {
                Text("PR #\(pullRequestNumber)")
              } else if status.outcome == .active {
                Text("PR not created yet")
              }
              Text(status.mode.rawValue.capitalized)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
          }

          if let message = self.observation.message {
            Text(message)
              .font(.caption2)
              .foregroundStyle(self.observation.availability == .invalid ? .red : .secondary)
              .fixedSize(horizontal: false, vertical: true)
          } else if self.observation.availability == .live {
            Text("Controller-reported local phase · process identity verified")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.sectionTitle)
        .accessibilityValue(self.accessibilityValue(now: context.date))
        .accessibilityHint(
          "Local controller telemetry reports execution phase only. GitHub remains authoritative for pull request merge and Issue completion."
        )
      }
    }

    @ViewBuilder
    private func stageTrack(_ status: AutomationRuntimeStatus) -> some View {
      let effectivePhase = status.lastActivePhase ?? status.phase
      let currentStage = effectivePhase.stage
      let completed = status.outcome == .completed

      VStack(spacing: 4) {
        HStack(spacing: 4) {
          ForEach(AutomationRuntimeStage.allCases, id: \.self) { stage in
            Capsule()
              .fill(
                completed || stage.rawValue <= currentStage.rawValue
                  ? self.accentColor : Color.secondary.opacity(0.16)
              )
              .frame(height: 4)
          }
        }

        HStack(spacing: 0) {
          ForEach(AutomationRuntimeStage.allCases, id: \.self) { stage in
            Text(stage.title)
              .font(.system(size: 8, weight: stage == currentStage ? .semibold : .regular))
              .foregroundStyle(
                stage == currentStage ? self.accentColor : Color.secondary.opacity(0.55)
              )
              .frame(maxWidth: .infinity)
          }
        }
      }
    }

    private var sectionTitle: String {
      switch self.observation.availability {
      case .live: "Current automation"
      case .terminal: "Last controller outcome"
      case .stale: "Local status needs attention"
      case .invalid: "Local phase unavailable"
      case .absent: "Local phase"
      }
    }

    private var badgeText: String {
      switch self.observation.availability {
      case .live: "LIVE"
      case .terminal: self.observation.status?.outcome.rawValue.uppercased() ?? "TERMINAL"
      case .stale: "STALE"
      case .invalid: "INVALID"
      case .absent: "OFF"
      }
    }

    private var accentColor: Color {
      switch self.observation.availability {
      case .live: .blue
      case .terminal:
        self.observation.status?.outcome == .completed ? .green : .orange
      case .stale: .orange
      case .invalid: .red
      case .absent: .secondary
      }
    }

    private var symbolName: String {
      switch self.observation.availability {
      case .live: "waveform.path.ecg"
      case .terminal:
        self.observation.status?.outcome == .completed
          ? "checkmark.circle.fill" : "stop.circle.fill"
      case .stale: "exclamationmark.arrow.triangle.2.circlepath"
      case .invalid: "xmark.shield.fill"
      case .absent: "minus.circle"
      }
    }

    private func phaseTitle(_ status: AutomationRuntimeStatus) -> String {
      let base: String
      if status.outcome == .active {
        base = status.phase.title
      } else if let lastActivePhase = status.lastActivePhase, status.outcome != .completed {
        base = "\(status.phase.title) during \(lastActivePhase.title)"
      } else {
        base = status.phase.title
      }
      if let phaseDetail = status.phaseDetail, status.outcome == .active {
        return "\(base) · \(phaseDetail)"
      }
      return base
    }

    private func phaseTime(_ status: AutomationRuntimeStatus, now: Date) -> String {
      if status.outcome == .active {
        return RelativeTimeFormatter.compactDuration(from: status.phaseStartedAt, to: now)
      }
      return RelativeTimeFormatter.relativeDescription(from: status.updatedAt, to: now)
    }

    private func accessibilityValue(now: Date) -> String {
      guard let status = self.observation.status else {
        return self.observation.message ?? "No local runtime status"
      }
      var parts = [self.badgeText, self.phaseTitle(status), "Issue \(status.issueNumber)"]
      if let pullRequestNumber = status.pullRequestNumber {
        parts.append("pull request \(pullRequestNumber)")
      } else if status.outcome == .active {
        parts.append("pull request not created yet")
      }
      parts.append(self.phaseTime(status, now: now))
      if let message = self.observation.message { parts.append(message) }
      return parts.joined(separator: ", ")
    }
  }
#endif
