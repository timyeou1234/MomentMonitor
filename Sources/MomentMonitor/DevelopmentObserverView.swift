#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct DevelopmentObserverView: View {
    let diagnosis: DevelopmentDiagnosis

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 7) {
          Image(systemName: self.symbolName)
            .foregroundStyle(self.accentColor)
          Text("Development observer")
            .font(.caption.weight(.semibold))
          Spacer(minLength: 4)
          Text(self.diagnosis.source == .ollama ? "LOCAL AI" : "RULES")
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(self.accentColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(self.accentColor.opacity(0.10), in: Capsule())
        }

        Text(self.diagnosis.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 5) {
          Text(self.diagnosis.classification.title)
          Text("·")
          Text(self.diagnosis.recommendation.title)
          Spacer(minLength: 0)
          Text("READ ONLY")
        }
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(self.accentColor)
      }
      .padding(10)
      .background(self.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Development observer")
      .accessibilityValue(
        "\(self.diagnosis.classification.title). \(self.diagnosis.summary). \(self.diagnosis.recommendation.title). Read only."
      )
      .accessibilityHint("This observer cannot dispatch, repair, approve, or merge work.")
    }

    private var symbolName: String {
      switch self.diagnosis.classification {
      case .healthy: "checkmark.circle.fill"
      case .watch: "eye.fill"
      case .blockedTechnical: "wrench.and.screwdriver.fill"
      case .needsOwner: "person.crop.circle.badge.exclamationmark"
      case .stale: "clock.badge.exclamationmark"
      }
    }

    private var accentColor: Color {
      switch self.diagnosis.classification {
      case .healthy: .green
      case .watch: .orange
      case .blockedTechnical: .orange
      case .needsOwner: .red
      case .stale: .red
      }
    }
  }
#endif
