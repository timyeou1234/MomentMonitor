# Codex handoff: validate and repair Moment Monitor

## Goal

Treat this directory as an independent macOS menu-bar application. Run the complete validation matrix, fix every reproducible defect, and leave the branch in a reviewable state. Do not merge the pull request.

## Boundaries

- Do not modify any existing Moments product automation, scheduler, Codex task, PR Fast, labels, or issue state.
- Do not add GitHub mutation capabilities to Moment Monitor.
- Do not add dispatch, rerun, cancel, merge, comment, label, branch, checkout, or repository-sync controls.
- Completion still requires a merged automation PR and a closed originating Issue; a successful workflow alone is not completion.
- Keep `Scripts/check_read_only.sh` passing.
- Restrict changes to `tools/MomentMonitor/**` and the dedicated branch-only handoff validation workflow.

## Required validation

Run on the available environment:

```bash
cd tools/MomentMonitor
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
./Scripts/check_read_only.sh
bash -n Scripts/check_read_only.sh Scripts/package_app.sh Scripts/install_app.sh
```

On macOS also run:

```bash
./Scripts/package_app.sh
test -d "dist/Moment Monitor.app"
test -f "dist/MomentMonitor.zip"
codesign --verify --deep --strict "dist/Moment Monitor.app"
plutil -lint "dist/Moment Monitor.app/Contents/Info.plist"
```

Then inspect the implementation for issues not covered by existing tests, especially:

- GitHub REST pagination and status decoding;
- Issue/PR/workflow correlation;
- scheduler priority and dependency handling;
- stale or contradictory state classification;
- Finder-launched PATH resolution for `gh`;
- polling cancellation and Swift 6 concurrency correctness;
- menu-bar lifecycle, settings persistence, error display, and row links;
- packaging, ad-hoc signing, and app bundle structure;
- strict read-only enforcement and regression tests.

## Repair contract

- Add focused tests before or with each behavioral fix.
- Keep the app dependency-free unless a standard-library solution is not viable.
- Do not weaken tests or read-only checks to make validation pass.
- Commit fixes to the current PR branch.
- Finish with a concise summary of defects found, files changed, and exact commands/results.
