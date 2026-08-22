#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

forbidden='("POST"|"PATCH"|"PUT"|"DELETE"|--field|--raw-field|--input|"git"|/usr/bin/git|/opt/homebrew/bin/git|gh[[:space:]]+workflow[[:space:]]+run|gh[[:space:]]+run[[:space:]]+(rerun|cancel)|gh[[:space:]]+pr[[:space:]]+(merge|close|reopen|edit)|gh[[:space:]]+issue[[:space:]]+(edit|comment|close|reopen))'

if grep -RInEi --include="*.swift" "$forbidden" Sources; then
  echo "Read-only contract violation found in production sources." >&2
  exit 1
fi

runtime_reader="Sources/MomentMonitorCore/AutomationRuntimeStatusReader.swift"
grep -q 'O_RDONLY' "$runtime_reader"
grep -q 'O_NOFOLLOW' "$runtime_reader"
local_write_forbidden='O_WRONLY|O_RDWR|createFile|removeItem|moveItem|replaceItem|setAttributes|\.write\('
if grep -nE "$local_write_forbidden" "$runtime_reader"; then
  echo "Local runtime reader contains a write-capable operation." >&2
  exit 1
fi

swift test

echo "Read-only contract and tests passed."
