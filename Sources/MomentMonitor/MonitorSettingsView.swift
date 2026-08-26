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

        Section("Local development observer") {
          Toggle(
            "Use local Qwen summaries", isOn: self.$store.localModelObserverEnabled)
          Label(
            "Only closed status enums and Issue/PR numbers are sent to oMLX on this Mac.",
            systemImage: "eye"
          )
          Text(
            "Issue bodies, comments, logs, commands, paths, credentials, prompts, responses, and checkpoint contents are excluded. Rules remain authoritative; the model cannot dispatch Codex or change automation."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Section("Phone dashboard") {
          Toggle(
            "Serve a private dashboard from this Mac", isOn: self.$store.mobileDashboardEnabled)
          HStack {
            Text("Local port")
            Spacer()
            TextField("Port", value: self.$store.mobileDashboardPort, format: .number)
              .frame(width: 90)
              .multilineTextAlignment(.trailing)
          }
          if let validationMessage = self.store.mobileDashboardValidationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
          }
          Label(
            self.store.mobileDashboardStatusText,
            systemImage: self.store.mobileDashboardStatusIsError
              ? "exclamationmark.triangle.fill" : "iphone.gen3"
          )
          .font(.caption)
          .foregroundStyle(self.store.mobileDashboardStatusIsError ? .red : .secondary)

          HStack {
            Button("Open Local Dashboard") {
              self.store.openMobileDashboard()
            }
            .disabled(self.store.mobileDashboardLocalURL == nil)
            Button("Copy Tailscale Command") {
              self.store.copyTailscaleCommand()
            }
            .disabled(!self.store.mobileDashboardEnabled)
          }

          Text(
            "The server is off by default and binds only to 127.0.0.1. Tailscale Serve can privately proxy it to devices in your tailnet. Never use Tailscale Funnel for this dashboard."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text(self.store.tailscaleServeCommand)
            .font(.caption.monospaced())
            .textSelection(.enabled)
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
      .frame(width: 540, height: 760)
      .padding()
    }
  }
#endif
