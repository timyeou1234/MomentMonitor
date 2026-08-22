#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct ProjectProgressView: View {
    let progress: ProjectProgress
    let isLoaded: Bool
    let isRefreshing: Bool

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("Project progress")
            .font(.subheadline.weight(.semibold))

          Spacer()

          Text(self.summaryText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }

        if self.isLoaded {
          ProgressView(
            value: Double(self.progress.completedCount),
            total: Double(max(1, self.progress.totalCount))
          )
          .progressViewStyle(.linear)
          .tint(self.progress.isComplete ? .green : .accentColor)
        } else if self.isRefreshing {
          ProgressView()
            .controlSize(.small)
        } else {
          ProgressView(value: 0, total: 1)
            .progressViewStyle(.linear)
            .tint(.secondary)
        }

        Text(self.scopeText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Project progress")
      .accessibilityValue(self.accessibilityValue)
      .accessibilityHint(
        "Counts tracked automation Issues. Completion requires a merged pull request and a closed originating Issue."
      )
    }

    private var summaryText: String {
      guard self.isLoaded else { return self.isRefreshing ? "Reading…" : "Unavailable" }
      guard self.progress.totalCount > 0 else { return "No tracked work" }
      return
        "\(self.progress.completedCount) of \(self.progress.totalCount) · \(self.progress.percentage)%"
    }

    private var scopeText: String {
      guard self.isLoaded else {
        return self.isRefreshing
          ? "Reading tracked automation Issues…" : "Available after a successful refresh"
      }
      return "Tracked automation Issues · merged PR + closed Issue"
    }

    private var accessibilityValue: String {
      guard self.isLoaded else {
        return self.isRefreshing ? "Refreshing" : "Unavailable until refresh succeeds"
      }
      guard self.progress.totalCount > 0 else { return "No tracked automation Issues" }
      return
        "\(self.progress.percentage) percent, \(self.progress.completedCount) of \(self.progress.totalCount) tracked automation Issues completed"
    }
  }
#endif
