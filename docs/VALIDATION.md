# Validation

## Completed in the implementation environment

```text
Swift 6.2.1 / x86_64 Linux
19 XCTest cases
0 failures
strict warnings-as-errors build
swift-format strict lint
read-only source scan
macOS-target syntax parse for every SwiftUI/AppKit source
shell syntax validation for packaging scripts
```

Commands:

```bash
swift test -Xswiftc -warnings-as-errors
./Scripts/check_read_only.sh
swift-format lint --strict --recursive Sources Tests Package.swift
swiftc -frontend -parse -target arm64-apple-macosx14.0 Sources/MomentMonitor/*.swift
bash -n Scripts/check_read_only.sh Scripts/package_app.sh
```

## Deliberately not claimed

The implementation environment is Linux and has no Apple SDK. The macOS code was syntax-parsed for the macOS target, but AppKit/SwiftUI type-checking, signing and launching the final `.app` must run on a Mac:

```bash
./Scripts/package_app.sh
open "dist/Moment Monitor.app"
```

No command in this validation writes to `timyeou1234/Moment`.
