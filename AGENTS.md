# Moment Monitor agent guide

## Goal

Maintain a read-only macOS viewer for Moments automation. GitHub state remains
the authority; an optional versioned local controller-status file may add exact
phase detail without becoming an operational dependency.

## Non-negotiable boundary

- Never add a GitHub mutation endpoint or UI control.
- Never invoke git against the Moment checkout.
- Never ask GitHub workflows to publish observer state. The only permitted local
  integration is the credential-free, controller-owned
  `MomentAutomation/runtime/current.json` contract; viewer absence or failure
  must have no effect on automation.
- Never classify a successful workflow run as completed work; completion requires a merged automation PR and a closed originating Issue.
- Keep `Scripts/check_read_only.sh` passing.

## Commands

```bash
swift build --target MomentMonitorCore
swift test
./Scripts/check_read_only.sh
```

On macOS:

```bash
./Scripts/package_app.sh
open "dist/Moment Monitor.app"
```

## Architecture

- `MomentMonitorCore`: REST models, GET-only GitHub CLI client, dependency parser, run/PR correlation and deterministic state builder.
- `MomentMonitor`: macOS SwiftUI menu-bar UI and polling store.
- `Tests`: synthetic GitHub fixtures and state contract tests.

Prefer adding pure state-builder tests before changing UI. Avoid adding external packages unless the standard library and Foundation cannot satisfy the requirement.
