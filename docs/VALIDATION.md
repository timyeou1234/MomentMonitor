# Validation

## Completed before and after standalone repository extraction

```text
macOS 26.6.2 / Apple Silicon arm64
Xcode 26.6
Apple Swift 6.3.3
GitHub CLI 2.97.0
33 XCTest cases
0 failures
```

Validated boundaries:

- full Swift package build with warnings as errors;
- deterministic core tests, including bounded pagination, REST PR/run correlation, scheduler ordering, repair-attempt labels, case-insensitive status handling, Finder-style `gh` lookup, truthful local-runner state, and project-progress counting independent of visible row limits;
- strict GET-only source scan;
- Swift format lint and shell syntax;
- release app bundle, ad-hoc signature, plist, executable, license resources, and zip round-trip;
- bounded packaged-app launch smoke with a Finder-style minimal `PATH`;
- first install and in-place update through the one-command installer, including staging cleanup;
- installed-app launch from `~/Applications`, menu-bar popover presence, Settings command, and Settings window presence;
- project-progress model coverage for visible-row truncation, duplicate merged PRs, and no tracked work;
- installed v0.2.0 progress-bar rendering, percentage text, and scope disclosure, plus compiled combined accessibility label/value/hint semantics;
- authenticated GET-only live refresh against `timyeou1234/Moment`.

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

The isolated installer ran twice against the same destination, proving both first-install and update paths. The final app was then installed, signed, launched, and observed at `~/Applications/Moment Monitor.app`. After the live refresh, macOS Accessibility reported `Moment Monitor, 3 active items` for the status menu; the app menu exposed Settings and Quit; and Core Graphics reported the v0.2.0 440 × 694 status popover and 540 × 444 Settings window.

The v0.2.0 live GET-only refresh calculated 3 completed of 8 tracked automation Issues (38%). Its inputs cross-checked against the rendered lanes: 2 waiting, 1 running, 2 PR/checks, and 3 completed. The visual inspection confirmed that the progress bar, percentage, scope disclosure, scrolling content, and footer remained visible without overlap.

The current live GET-only refresh completed in 4.80 seconds. Workflow history remains bounded to the newest 100 runs; the previous all-history workflow request was stopped after 34.39 seconds and would have exceeded the app's 20-second command timeout.

## Deliberately not claimed

- Developer ID signing, notarization, external distribution, background auto-update, or App Store readiness;
- long-duration polling, sleep/wake, network-loss, or credential-expiry soak;
- exhaustive visual or assistive-technology conformance;
- visibility into local runner commands, files, model activity, or token usage;
- any GitHub or Moment automation mutation.
