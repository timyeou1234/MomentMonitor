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

            self.lifecycleTrack(status)

            if let strategy = AutomationStrategyProgress(observation: self.observation) {
              self.strategyTrack(strategy)
            }

            if self.observation.availability == .live, let activity = status.activity,
              activity.isRecent(at: context.date)
            {
              self.activitySummary(activity, now: context.date)
            }

            HStack(spacing: 7) {
              Text("Issue #\(status.issueNumber)")
              if let duration = status.observedDurationMilliseconds(
                for: status.issueNumber,
                at: context.date,
                runnerIsLive: self.observation.availability == .live
              ) {
                Text("Codex \(RelativeTimeFormatter.compactDuration(milliseconds: duration))")
              }
              if let pullRequestNumber = status.pullRequestNumber {
                Text("PR #\(pullRequestNumber)")
              } else if status.outcome == .active {
                Text("PR not created yet")
              }
              Text(status.mode.rawValue.capitalized)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
          } else if let status = self.observation.autonomousStatus {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
              Image(systemName: self.symbolName)
                .foregroundStyle(self.accentColor)
              Text(status.phase.title)
                .font(.callout.weight(.semibold))
              Spacer(minLength: 4)
              Text(
                RelativeTimeFormatter.relativeDescription(from: status.observedAt, to: context.date)
              )
              .font(.caption2.monospacedDigit())
              .foregroundStyle(.tertiary)
            }

            HStack(spacing: 4) {
              ForEach(AutomationRuntimeStage.allCases, id: \.self) { stage in
                let reached = stage.rawValue <= status.phase.stage.rawValue
                let isCurrent = stage == status.phase.stage && !status.phase.isTerminal
                Text(stage.title)
                  .font(.system(size: 7, weight: .bold, design: .rounded))
                  .foregroundStyle(
                    isCurrent ? Color.white : reached ? self.accentColor : .secondary
                  )
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 3)
                  .background(
                    isCurrent
                      ? self.accentColor
                      : reached ? self.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                    in: Capsule()
                  )
              }
            }

            HStack(spacing: 7) {
              if let issueNumber = status.issueNumber { Text("Issue #\(issueNumber)") }
              Text(status.role.rawValue.capitalized)
              if status.reviewRound > 0 { Text("Review \(status.reviewRound)") }
              if status.repairAttempt > 0 { Text("Repair \(status.repairAttempt)") }
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
            Text("Read-only observer · GitHub and the local controller remain authoritative")
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
          "Moment Monitor summarizes the controller lifecycle only. It cannot dispatch, approve, repair, or merge work."
        )
      }
    }

    private func activitySummary(_ activity: AutomationRuntimeActivity, now: Date) -> some View {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("LIVE ACTIVITY")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(.secondary)
          Text(activity.source.displayName.uppercased())
            .font(.system(size: 7, weight: .bold, design: .rounded))
            .foregroundStyle(self.accentColor)
          Spacer(minLength: 4)
          Text(RelativeTimeFormatter.relativeDescription(from: activity.observedAt, to: now))
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
        }

        HStack(spacing: 6) {
          Image(systemName: activity.state == .failed ? "exclamationmark.circle.fill" : "waveform")
            .foregroundStyle(activity.state == .failed ? .orange : self.accentColor)
          Text(activity.title)
            .font(.caption2.weight(.semibold))
          Spacer(minLength: 4)
          Text("\(activity.completedCommands) commands · \(activity.completedFileChanges) changes")
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(self.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
    }

    private func strategyTrack(_ strategy: AutomationStrategyProgress) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(strategy.title.uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(.secondary)
          Spacer(minLength: 4)
          Text(strategy.currentStepTitle)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(self.accentColor)
        }

        HStack(spacing: 4) {
          ForEach(Array(strategy.steps.enumerated()), id: \.offset) { _, step in
            Text(step.shortLabel)
              .font(.system(size: 7, weight: .bold, design: .rounded))
              .foregroundStyle(self.strategyForeground(step.state))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 3)
              .background(self.strategyBackground(step.state), in: Capsule())
              .overlay {
                Capsule()
                  .stroke(self.strategyBorder(step.state), lineWidth: 0.7)
              }
          }
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(strategy.accessibilitySummary)
    }

    private func strategyForeground(_ state: AutomationStrategyStepState) -> Color {
      switch state {
      case .completed: self.accentColor
      case .active: .white
      case .pending: .secondary
      case .halted: .orange
      }
    }

    private func strategyBackground(_ state: AutomationStrategyStepState) -> Color {
      switch state {
      case .completed: self.accentColor.opacity(0.16)
      case .active: self.accentColor
      case .pending: Color.secondary.opacity(0.08)
      case .halted: Color.orange.opacity(0.16)
      }
    }

    private func strategyBorder(_ state: AutomationStrategyStepState) -> Color {
      switch state {
      case .completed: self.accentColor.opacity(0.42)
      case .active: self.accentColor
      case .pending: Color.secondary.opacity(0.15)
      case .halted: Color.orange.opacity(0.55)
      }
    }

    @ViewBuilder
    private func lifecycleTrack(_ status: AutomationRuntimeStatus) -> some View {
      let effectivePhase = status.lastActivePhase ?? status.phase
      let currentStage = effectivePhase.lifecycleStage
      let completed = status.outcome == .completed

      VStack(alignment: .leading, spacing: 5) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("LIFECYCLE")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(.secondary)
          Spacer(minLength: 4)
          Text(completed ? "Completed" : currentStage.title)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(self.accentColor)
        }

        HStack(spacing: 4) {
          ForEach(AutomationLifecycleStage.allCases, id: \.self) { stage in
            let reached = completed || stage.rawValue <= currentStage.rawValue
            let isCurrent = !completed && stage == currentStage
            Text(stage.title)
              .font(.system(size: 7, weight: .bold, design: .rounded))
              .foregroundStyle(isCurrent ? Color.white : reached ? self.accentColor : .secondary)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 3)
              .background(
                isCurrent
                  ? self.accentColor
                  : reached ? self.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                in: Capsule()
              )
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
      case .terminal:
        self.observation.status?.outcome.rawValue.uppercased()
          ?? self.observation.autonomousStatus?.phase.rawValue.uppercased()
          ?? "TERMINAL"
      case .stale: "STALE"
      case .invalid: "INVALID"
      case .absent: "OFF"
      }
    }

    private var accentColor: Color {
      switch self.observation.availability {
      case .live: .blue
      case .terminal:
        self.observation.status?.outcome == .completed
          || self.observation.autonomousStatus?.phase == .completed ? .green : .orange
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
          || self.observation.autonomousStatus?.phase == .completed
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
      if let status = self.observation.autonomousStatus {
        var parts = [
          self.badgeText,
          status.phase.title,
          "lifecycle \(status.phase.stage.title)",
          status.issueNumber.map { "Issue \($0)" } ?? "Issue unavailable",
          status.role.rawValue,
          RelativeTimeFormatter.relativeDescription(from: status.observedAt, to: now),
        ]
        if status.reviewRound > 0 { parts.append("review round \(status.reviewRound)") }
        if status.repairAttempt > 0 { parts.append("repair attempt \(status.repairAttempt)") }
        if let message = self.observation.message { parts.append(message) }
        return parts.joined(separator: ", ")
      }
      guard let status = self.observation.status else {
        return self.observation.message ?? "No local runtime status"
      }
      let effectivePhase = status.lastActivePhase ?? status.phase
      var parts = [
        self.badgeText,
        self.phaseTitle(status),
        "lifecycle \(effectivePhase.lifecycleStage.title)",
        "Issue \(status.issueNumber)",
      ]
      if let pullRequestNumber = status.pullRequestNumber {
        parts.append("pull request \(pullRequestNumber)")
      } else if status.outcome == .active {
        parts.append("pull request not created yet")
      }
      parts.append(self.phaseTime(status, now: now))
      if let strategy = AutomationStrategyProgress(observation: self.observation) {
        parts.append(strategy.accessibilitySummary)
      }
      if let activity = status.activity, self.observation.availability == .live,
        activity.isRecent(at: now)
      {
        parts.append(
          "\(activity.source.displayName), \(activity.title), "
            + "\(activity.completedCommands) commands and "
            + "\(activity.completedFileChanges) file changes"
        )
      }
      if let message = self.observation.message { parts.append(message) }
      return parts.joined(separator: ", ")
    }
  }
#endif
