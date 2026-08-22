# Validation

## v0.4.0 phone-dashboard candidate

```text
macOS 26.6.2 / Apple Silicon arm64
Xcode 26.6
Apple Swift 6.3.3
GitHub CLI 2.97.0
49 XCTest cases
0 failures
```

Validated boundaries:

- full Swift package build with warnings as errors;
- deterministic core tests, including bounded pagination, REST PR/run correlation, scheduler ordering, repair-attempt labels, case-insensitive status handling, Finder-style `gh` lookup, truthful local-runner state, and project-progress counting independent of visible row limits;
- strict local runtime-status tests covering a live PID, dead-PID stale detection, terminal outcomes, repository mismatch, unknown or contradictory fields, owner-only permissions, symbolic-link rejection, and the 16 KiB size boundary;
- reconciliation tests proving that a precise local phase replaces only the matching broad GitHub running row, while GitHub remains authoritative for merged/closed completion;
- a sanitized, versioned mobile snapshot that omits run ID, PID and Git SHAs while preserving exact phase, progress and lane truth;
- real loopback-server tests for routes, GET/HEAD-only methods, Host validation, security headers, bounded requests and bundled mobile-first assets;
- source scans that reject public binding, CORS, external web assets, `innerHTML`, `localStorage` and public `.ts.net` matching;
- strict GET-only source scan;
- Swift format lint and shell syntax;
- release app bundle, ad-hoc signature, plist, executable, license resources, and zip round-trip;
- packaged-app launch with a synthetic, credential-free local phase record;
- in-place v0.4.0 installation, ad-hoc signature verification, Finder-style launch from `~/Applications`, and version/build confirmation (`0.4.0` / `4`);
- packaged and installed dashboard HTTP smoke with real Moment state, confirming the listener is only `127.0.0.1:48127`, the API reports the live Luna/Sol phase, and security headers forbid caching, framing and cross-origin access;
- packaged resource loading without falling back to the build worktree, so installed startup does not depend on Documents-folder access or the source checkout remaining present;
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
test -f "dist/Moment Monitor.app/Contents/Resources/MobileDashboard/index.html"
plutil -lint "dist/Moment Monitor.app/Contents/Info.plist"
codesign --verify --deep --strict "dist/Moment Monitor.app"
MOMENT_MONITOR_INSTALL_DIR=/private/tmp/<isolated-test-root> ./Scripts/install_app.sh
./Scripts/install_app.sh
git diff --check
```

The previous v0.2.0 install validation proved first-install and update paths, status-popover and Settings-window presence, and project-progress rendering. The v0.3.0 validation proved the precise local phase contract. The v0.4.0 in-place installer, signature, installed version/build, Finder launch and localhost-only dashboard checks passed against real controller state; during validation the dashboard truthfully followed Issue #345 from Luna development to Sol review.

The local phase card polls independently every second. GitHub polling remains bounded and slower; local telemetry never asserts that a PR merged or an Issue closed. An interrupted controller leaves a dead PID and is shown as stale, while a terminal record retains the last active phase.

The phone page polls the app's in-memory snapshot every second while visible and every 10 seconds while hidden. Browser suspension can delay a background page; returning to the page triggers an immediate retry. Remote HTTPS access is intentionally delegated to Tailscale Serve and its ACL rather than implemented as a public listener in Moment Monitor.

## Deliberately not claimed

- Developer ID signing, notarization, external distribution, background auto-update, or App Store readiness;
- long-duration polling, sleep/wake, network-loss, or credential-expiry soak;
- physical iPhone rendering, iOS Add to Home Screen behavior, or a completed Tailscale tailnet login from this deterministic repository validation;
- exhaustive visual or assistive-technology conformance; automated menu-bar capture was not reliable with the current auto-hidden multi-display menu bar, so no new v0.3.0 screenshot is claimed;
- visibility into local runner commands, changed files, prompts, responses, findings, or token usage;
- any GitHub or Moment automation mutation.
