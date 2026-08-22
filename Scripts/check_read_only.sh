#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

forbidden='("POST"|"PATCH"|"PUT"|"DELETE"|--field|--raw-field|--input|"git"|/usr/bin/git|/opt/homebrew/bin/git|gh[[:space:]]+workflow[[:space:]]+run|gh[[:space:]]+run[[:space:]]+(rerun|cancel)|gh[[:space:]]+pr[[:space:]]+(merge|close|reopen|edit)|gh[[:space:]]+issue[[:space:]]+(edit|comment|close|reopen))'

if grep -RInEi --include="*.swift" "$forbidden" Sources; then
  echo "Read-only contract violation found in production sources." >&2
  exit 1
fi

swift test

echo "Read-only contract and tests passed."
