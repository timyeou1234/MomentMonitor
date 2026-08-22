#if os(macOS)
  import SwiftUI

  struct MonitorSettingsView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
      Form {
        Section("Repository") {
          TextField("owner/name", text: self.$store.repositoryText)
            .textFieldStyle(.roundedBorder)
          Text("The default is timyeou1234/Moment. The monitor never writes to this repository.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section("Refresh") {
          Picker("Interval", selection: self.$store.refreshIntervalSeconds) {
            Text("15 seconds").tag(15)
            Text("30 seconds").tag(30)
            Text("1 minute").tag(60)
            Text("2 minutes").tag(120)
            Text("5 minutes").tag(300)
          }
          Stepper(
            "Completed items: \(self.store.completedItemLimit)",
            value: self.$store.completedItemLimit,
            in: 1...30
          )
        }

        Section("Read-only boundary") {
          Label(
            "Only gh auth status and gh api --method GET are allowed.", systemImage: "lock.shield")
          Text(
            "The app has no controls for dispatch, rerun, cancel, label mutation, comments, merge, branch changes, or local repository sync."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text(
            "Prerequisite: install GitHub CLI and run gh auth login with access to the private Moment repository."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        HStack {
          Spacer()
          Button("Apply and Refresh") {
            self.store.applyPreferences()
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .formStyle(.grouped)
      .frame(width: 520, height: 390)
      .padding()
    }
  }
#endif
