#if os(macOS)
  import MomentMonitorCore
  import SwiftUI

  struct MonitorSectionView: View {
    let lane: MonitorLane
    let items: [MonitorItem]

    var body: some View {
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 6) {
          Text(self.lane.title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
          Text("\(self.items.count)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
          Spacer()
        }

        VStack(spacing: 1) {
          ForEach(self.items) { item in
            MonitorRowView(item: item)
            if item.id != self.items.last?.id {
              Divider()
                .padding(.leading, 31)
            }
          }
        }
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }
#endif
