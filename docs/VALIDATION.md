# Validation

## v0.3.0 precise-phase candidate

```text
macOS 26.6.2 / Apple Silicon arm64
Xcode 26.6
Apple Swift 6.3.3
GitHub CLI 2.97.0
45 XCTest cases
0 failures
```

Validated boundaries:

- full Swift package build with warnings as errors;
- deterministic core tests, including bounded pagination, REST PR/run correlation, scheduler ordering, repair-attempt labels, case-insensitive status handling, Finder-style `gh` lookup, truthful local-runner state, and project-progress counting independent of visible row limits;
- strict local runtime-status tests covering a live PID, dead-PID stale detection, terminal outcomes, repository mismatch, unknown or contradictory fields, owner-only permissions, symbolic-link rejection, and the 16 KiB size boundary;
- reconciliation tests proving that a precise local phase replaces only the matching broad GitHub running row, while GitHub remains authoritative for merged/closed completion;
- strict GET-only source scan;
- Swift format lint and shell syntax;
- release app bundle, ad-hoc signature, plist, executable, license resources, and zip round-trip;
- packaged-app launch with a synthetic, credential-free local phase record;
- in-place v0.3.0 installation, ad-hoc signature verification, launch from `~/Applications`, and version/build confirmation (`0.3.0` / `3`);
- project-progress model coverage for visible-row truncation, duplicate merged PRs, and no tracked work;
- compiled five-stage phase track, elapsed-time updates, Issue/PR identity, and combined accessibility label/value/hint semantics;
- authenticated GET-only live refresh against `timyeou1234/Moment` remains the only GitHub integration.

Commands:

```bash
swift test -Xswiftc -warnings-as-errors
./Scripts/check_read_only.sh
bash -n Scripts/check_read_only.sh Scripts/package_app.sh Scripts/install_app.sh
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
./Scripts/package_app.sh
test -x "dist/Moment Monitor.app/Contents/MacOS/MomentMonitor"
test -f "dist/MomentMonitor.zip"
plutil -lint "dist/Moment Monitor.app/Contents/Info.plist"
codesign --verify --deep --strict "dist/Moment Monitor.app"
MOMENT_MONITOR_INSTALL_DIR=/private/tmp/<isolated-test-root> ./Scripts/install_app.sh
./Scripts/install_app.sh
git diff --check
```

The previous v0.2.0 install validation proved first-install and update paths, status-popover and Settings-window presence, and project-progress rendering. The v0.3.0 in-place installer, signature, installed version/build, and bounded launch checks passed before tagging. A packaged v0.3.0 candidate was also launched against a synthetic controller record owned by the current user; the real Swift reader and Python producer agree on the versioned schema, bounded fields, mode-0600 file, and live-PID requirement.

The local phase card polls independently every second. GitHub polling remains bounded and slower; local telemetry never asserts that a PR merged or an Issue closed. An interrupted controller leaves a dead PID and is shown as stale, while a terminal record retains the last active phase.

## Deliberately not claimed

- Developer ID signing, notarization, external distribution, background auto-update, or App Store readiness;
- long-duration polling, sleep/wake, network-loss, or credential-expiry soak;
- exhaustive visual or assistive-technology conformance; automated menu-bar capture was not reliable with the current auto-hidden multi-display menu bar, so no new v0.3.0 screenshot is claimed;
- visibility into local runner commands, changed files, prompts, responses, findings, or token usage;
- any GitHub or Moment automation mutation.
