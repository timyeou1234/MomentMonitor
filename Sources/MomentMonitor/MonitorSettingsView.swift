#if os(macOS)
  import SwiftUI

  struct MonitorSettingsView: View {
    @EnvironmentObject private var store: MonitorStore

    var body: some View {
      Form {
        Section("Repository") {
          TextField("owner/name", text: self.$store.repositoryText)
            .textFieldStyle(.roundedBorder)
            .onChange(of: self.store.repositoryText) {
              self.store.clearSettingsFeedback()
            }
          if let validationMessage = self.store.repositoryValidationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
          }
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

        Section("Local phase telemetry") {
          Label(
            "Reads the controller-owned runtime/current.json file when available.",
            systemImage: "waveform.path.ecg"
          )
          Text(
            "The file is optional, credential-free, and never used as merge or completion evidence. Unsafe permissions, unknown fields, dead processes, and schema mismatches fail closed."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        if let feedback = self.store.settingsFeedback {
          Label(
            feedback,
            systemImage: self.store.settingsFeedbackIsError
              ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
          )
          .font(.caption)
          .foregroundStyle(self.store.settingsFeedbackIsError ? .red : .green)
        }

        HStack {
          Spacer()
          Button {
            Task { await self.store.applyPreferences() }
          } label: {
            if self.store.isRefreshing {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Apply and Refresh")
            }
          }
          .keyboardShortcut(.defaultAction)
          .disabled(
            self.store.repositoryValidationMessage != nil || self.store.isRefreshing)
        }
      }
      .formStyle(.grouped)
      .frame(width: 520, height: 480)
      .padding()
    }
  }
#endif
