#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct AutomationWatchdogView: View {
    let observation: AutomationWatchdogObservation

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("ACTIVE AUTO WATCHDOG")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(self.observation.status?.state.title ?? "Observer status unavailable")
              .font(.subheadline.weight(.semibold))
          }
          Spacer()
          Text(self.observation.badgeLabel)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(self.tint.opacity(0.14), in: Capsule())
            .foregroundStyle(self.tint)
        }

        if let status = self.observation.status {
          Text(
            "\(status.model) · \(status.requiredObservations) matching observations · confidence ≥ \(status.confidenceThreshold, format: .percent.precision(.fractionLength(0)))"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)

          ForEach(Array(status.workers.enumerated()), id: \.offset) { _, worker in
            WatchdogWorkerRow(worker: worker)
          }
        } else if let message = self.observation.message {
          Text(message)
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .accessibilityElement(children: .combine)
    }

    private var tint: Color {
      switch self.observation.status?.state {
      case .takeover, .unblocking: .orange
      case .suspectedStall: .yellow
      case .unavailable: .red
      case .idle, .observing: .green
      case nil: .secondary
      }
    }

  }

  private struct WatchdogWorkerRow: View {
    let worker: AutomationWatchdogWorker

    var body: some View {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: self.iconName)
          .foregroundStyle(self.iconColor)
        VStack(alignment: .leading, spacing: 2) {
          Text("Issue #\(self.worker.issueNumber) · \(self.worker.phase) · \(self.worker.role)")
            .font(.caption.weight(.medium))
          Text(self.detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
          if let decision = self.worker.decision {
            Text(self.decisionText(decision))
              .font(.caption2)
              .foregroundStyle(decision.action == .observe ? Color.secondary : Color.orange)
          }
        }
        Spacer(minLength: 0)
      }
    }

    private var iconName: String {
      self.worker.process.activity == "working" ? "waveform.path.ecg" : "eye"
    }

    private var iconColor: Color {
      self.worker.process.activity == "working" ? .green : .secondary
    }

    private var detail: String {
      let model = self.worker.modelAvailable ? "oMLX online" : "oMLX unavailable"
      return
        "\(self.worker.workerID) · \(self.worker.process.activityKind) \(self.worker.process.activity) · \(model)"
    }

    private func decisionText(_ decision: AutomationWatchdogDecision) -> String {
      let percent = Int((decision.confidence * 100).rounded())
      return "\(decision.summary) \(percent)% · \(decision.streak)/\(decision.requiredStreak)"
    }
  }
#endif
