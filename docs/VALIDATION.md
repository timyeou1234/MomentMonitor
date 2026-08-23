# Validation

## v0.4.4 multi-round-strategy candidate

```text
macOS 26.6.2 / Apple Silicon arm64
Xcode 26.6
Apple Swift 6.3.3
GitHub CLI 2.97.0
59 XCTest cases
0 failures
```

Validated boundaries:

- full Swift package build with warnings as errors;
- deterministic core tests, including bounded pagination, REST PR/run correlation, scheduler ordering, repair-attempt labels, case-insensitive status handling, Finder-style `gh` lookup, truthful local-runner state, and M1 closed/total counting independent of visible row limits;
- strict local runtime-status tests covering a live PID, dead-PID stale detection, terminal outcomes, repository mismatch, unknown or contradictory fields, owner-only permissions, symbolic-link rejection, and the 16 KiB size boundary;
- reconciliation tests proving that a precise local phase replaces only the matching broad GitHub running row, while GitHub remains authoritative for merged/closed completion;
- a sanitized, versioned mobile snapshot that omits run ID, PID and Git SHAs while preserving exact phase, progress and lane truth;
- an exact read-only Codex App Server allow-list, bounded response decoding, Finder-style executable discovery, quota range validation, and Unavailable failure behavior;
- Codex capacity rendering from the canonical rate-limit bucket as remaining percentage, window duration and reset time without exposing plan identity or raw token activity;
- mobile stage rendering maps the schema-v3 integer stage value to the matching five-stage position, with a regression assertion that `sol_review` encodes as Review (`3`);
- a pure multi-round strategy derivation distinguishes review, correction, PR Fast validation, halted checkpoints and the unbounded Final Sol High goal without inferring a pass or percentage;
- Mac and mobile strategy tracks consume the same derived model; the mobile snapshot adds only bounded phase/counter labels and no prompt, response, finding or process identity;
- real loopback-server tests for routes, GET/HEAD-only methods, Host validation, security headers, bounded requests and bundled mobile-first assets;
- source scans that reject public binding, CORS, external web assets, `innerHTML`, `localStorage` and public `.ts.net` matching;
- strict GET-only source scan;
- Swift format lint and shell syntax;
- release app bundle, ad-hoc signature, plist, executable, license resources, and zip round-trip;
- packaged-app launch with a synthetic, credential-free local phase record;
- in-place v0.4.4 installation, ad-hoc signature verification, Finder-style launch from `~/Applications`, and version/build confirmation (`0.4.4` / `8`);
- packaged and installed dashboard HTTP smoke with real Moment state, confirming the listener is only `127.0.0.1:48127`, the API preserves the bounded runtime result, and security headers forbid caching, framing and cross-origin access;
- packaged resource loading without falling back to the build worktree, so installed startup does not depend on Documents-folder access or the source checkout remaining present;
- M1-progress model coverage for visible-row truncation, closed Issues without automation PRs, duplicate merged PRs, non-M1 exclusion, and no M1 scope;
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

The previous v0.2.0 install validation proved first-install and update paths, status-popover and Settings-window presence, and project-progress rendering. The v0.3.0 validation proved the precise local phase contract. The v0.4.0 validation proved the private phone dashboard and physical iPhone access. The v0.4.1 correction replaced the automation-lifecycle ratio with the repository owner's required closed-M1-Issues / all-M1-Issues definition. The v0.4.2 candidate added official read-only Codex rate-limit reporting and advanced the mobile snapshot to schema v3. The v0.4.3 correction aligned the phone's five-stage rendering with the numeric v3 wire value.

The local phase card polls independently every second. GitHub polling remains bounded and slower; local telemetry never asserts that a PR merged or an Issue closed. An interrupted controller leaves a dead PID and is shown as stale, while a terminal record retains the last active phase.

The phone page polls the app's in-memory snapshot every second while visible and every 10 seconds while hidden. Browser suspension can delay a background page; returning to the page triggers an immediate retry. Remote HTTPS access is intentionally delegated to Tailscale Serve and its ACL rather than implemented as a public listener in Moment Monitor.

The phone page exposes an explicit Refresh retry and separately renders the latest source-data timestamp from GitHub snapshot generation, runtime telemetry, or Codex usage. The HTTP receipt timestamp remains transport-only and cannot make unchanged data look newly updated.

## Deliberately not claimed

- Developer ID signing, notarization, external distribution, background auto-update, or App Store readiness;
- long-duration polling, sleep/wake, network-loss, or credential-expiry soak;
- physical iPhone rendering, iOS Add to Home Screen behavior, or a completed Tailscale tailnet login from this deterministic repository validation;
- exhaustive visual or assistive-technology conformance; automated menu-bar capture was not reliable with the current auto-hidden multi-display menu bar, so no new v0.3.0 screenshot is claimed;
- visibility into local runner commands, changed files, prompts, responses, findings, or raw token activity;
- any GitHub or Moment automation mutation.

## Installed v0.4.1 observation

- The installed macOS app reported dashboard schema `2` and M1 progress `16 / 161` through both the localhost API and the private Tailscale HTTPS route.
- The dashboard listener remained bound to localhost and Tailscale Funnel remained disabled.
- This live observation verifies the corrected count and private transport at that moment; it does not replace physical-iPhone validation of the corrected version.

## Installed v0.4.2 observation

- The installed app reported version/build `0.4.2` / `6`; its localhost and private Tailscale APIs both returned mobile schema `3` and the same live Codex rate-limit observation.
- The canonical Codex quota bucket reported `39%` used, so the UI rendered `61% remaining`, a weekly window, and the server-provided reset time. No raw token activity or account identity was included in the mobile snapshot.
- A 390 × 844 browser viewport rendered the Codex capacity card without horizontal overflow and exposed a `61% Codex capacity remaining` progressbar label. This responsive browser check is not a physical-iPhone claim.
- The listener remained bound to `127.0.0.1:48127`, Tailscale Serve continued to proxy the private HTTPS route, and Funnel remained disabled.

## Installed v0.4.3 observation

- The installed app reported version/build `0.4.3` / `7`, and its live schema-v3 snapshot reported `sol_review` with `activeStage: 3` for Issue #61.
- At a 390 × 844 browser viewport, Prepare through Review rendered with the completed gradient, Review was the only active label, and Publish remained unfilled. The page had no horizontal overflow.
- This verifies the responsive browser rendering and exact live phase mapping; it is not a physical-iPhone accessibility claim.

## Installed v0.4.4 observation

- The installed app reported version/build `0.4.4` / `8`. The live #61 record rendered Final Sol High as one active durable goal with `Until pass or a terminal boundary`, not a finite percentage.
- An isolated, credential-free v1 fixture exercised `sol_review`, round 2 of 4, repair attempt 1 through the packaged app. The API emitted `R1/C1` completed, `R2` active and `C2/R3/C3/R4` pending.
- At a 390 × 844 browser viewport, all seven checkpoints fit within the Current Automation card, Review remained the active macro stage, and the page had no horizontal overflow. The fixture was deleted and the installed app was restored to the real controller state immediately afterward.
- The synthetic responsive check does not claim physical-iPhone accessibility conformance or alter the controller-owned runtime record.
