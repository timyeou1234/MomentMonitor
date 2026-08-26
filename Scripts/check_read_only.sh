#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

forbidden='("POST"|"PATCH"|"PUT"|"DELETE"|--field|--raw-field|--input|"git"|/usr/bin/git|/opt/homebrew/bin/git|gh[[:space:]]+workflow[[:space:]]+run|gh[[:space:]]+run[[:space:]]+(rerun|cancel)|gh[[:space:]]+pr[[:space:]]+(merge|close|reopen|edit)|gh[[:space:]]+issue[[:space:]]+(edit|comment|close|reopen))'

if grep -RInEi --include="*.swift" --exclude="OMLXDevelopmentObserverClient.swift" "$forbidden" Sources; then
  echo "Read-only contract violation found in production sources." >&2
  exit 1
fi

omlx_observer="Sources/MomentMonitorCore/OMLXDevelopmentObserverClient.swift"
grep -q 'defaultEndpoint = URL(string: "http://127.0.0.1:8011")' "$omlx_observer"
grep -q 'defaultModel = "Qwen3.5-0.8B-MLX-4bit"' "$omlx_observer"
grep -q '\["127.0.0.1", "localhost", "::1"\].contains(host)' "$omlx_observer"
grep -q 'request.httpMethod = "POST"' "$omlx_observer"
grep -q 'chatTemplateArguments: OMLXChatTemplateArguments(enableThinking: false)' "$omlx_observer"
if grep -nE 'https://|0\.0\.0\.0|GH_TOKEN|GITHUB_TOKEN|/api/(generate|embeddings|pull|push|create|copy|delete)' "$omlx_observer"; then
  echo "Local model observer exceeds its loopback read-only inference boundary." >&2
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

ox_reader="Sources/MomentMonitorCore/OxAuditStatus.swift"
grep -q 'O_RDONLY' "$ox_reader"
grep -q 'O_NOFOLLOW' "$ox_reader"
if grep -nE "$local_write_forbidden" "$ox_reader"; then
  echo "Local Ox status reader contains a write-capable operation." >&2
  exit 1
fi

dashboard_server="Sources/MomentMonitorCore/MobileDashboardServer.swift"
grep -q 'loopbackHost = "127.0.0.1"' "$dashboard_server"
grep -q 'method == "GET" || method == "HEAD"' "$dashboard_server"
grep -q 'Content-Security-Policy:' "$dashboard_server"
grep -q 'Cache-Control: no-store' "$dashboard_server"
if grep -nE '0\.0\.0\.0|Access-Control-Allow-Origin|hasPrefix\("\.ts\.net"\)' "$dashboard_server"; then
  echo "Mobile dashboard weakens the localhost or same-origin boundary." >&2
  exit 1
fi
if grep -RInE 'https?://|innerHTML|localStorage' Sources/MomentMonitorCore/MobileDashboard; then
  echo "Mobile dashboard assets contain an external origin or persistent private cache." >&2
  exit 1
fi

codex_usage_reader="Sources/MomentMonitorCore/CodexUsageClient.swift"
grep -q 'account/rateLimits/read' "$codex_usage_reader"
if grep -nE 'account/usage/read|account/rateLimitResetCredit/consume|account/sendAddCreditsNudgeEmail|thread/start|turn/start' "$codex_usage_reader"; then
  echo "Codex usage integration exceeds the read-only rate-limit boundary." >&2
  exit 1
fi

install_script="Scripts/install_app.sh"
grep -q 'MOMENT_MONITOR_ALLOW_REINSTALL' "$install_script"
grep -q 'candidate_build <= installed_build' "$install_script"

swift test

echo "Read-only contract and tests passed."
