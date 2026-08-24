#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "install_app.sh must run on macOS." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_root="${MOMENT_MONITOR_INSTALL_DIR:-${HOME}/Applications}"
allow_reinstall="${MOMENT_MONITOR_ALLOW_REINSTALL:-0}"

if [[ "$install_root" != /* || "$install_root" == "/" ]]; then
  echo "MOMENT_MONITOR_INSTALL_DIR must be an absolute directory other than /." >&2
  exit 1
fi
if [[ "$allow_reinstall" != "0" && "$allow_reinstall" != "1" ]]; then
  echo "MOMENT_MONITOR_ALLOW_REINSTALL must be 0 or 1." >&2
  exit 1
fi

"$root/Scripts/package_app.sh"

source_app="$root/dist/Moment Monitor.app"
destination="$install_root/Moment Monitor.app"
mkdir -p "$install_root"
staging="$(mktemp -d "$install_root/.moment-monitor-install.XXXXXX")"
staged_app="$staging/Moment Monitor.app"
previous_app="$staging/Previous Moment Monitor.app"
backup_moved=false

cleanup() {
  set +e
  if $backup_moved && [[ ! -d "$destination" && -d "$previous_app" ]]; then
    mv "$previous_app" "$destination"
  fi
  case "$staging" in
    "$install_root"/.moment-monitor-install.*) rm -rf -- "$staging" ;;
  esac
}
trap cleanup EXIT INT TERM

ditto "$source_app" "$staged_app"
test -x "$staged_app/Contents/MacOS/MomentMonitor"
plutil -lint "$staged_app/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$staged_app"

candidate_info="$staged_app/Contents/Info.plist"
if ! candidate_build="$(plutil -extract CFBundleVersion raw "$candidate_info" 2>/dev/null)" \
  || [[ ! "$candidate_build" =~ ^[0-9]+$ ]]; then
  echo "Candidate app has an invalid build number." >&2
  exit 1
fi

if [[ -e "$destination" && ! -d "$destination" ]]; then
  echo "Install destination exists but is not an app directory: $destination" >&2
  exit 1
fi
if [[ -d "$destination" ]]; then
  installed_info="$destination/Contents/Info.plist"
  if ! installed_build="$(plutil -extract CFBundleVersion raw "$installed_info" 2>/dev/null)" \
    || [[ ! "$installed_build" =~ ^[0-9]+$ ]]; then
    echo "Installed app has an invalid build number; refusing to replace it." >&2
    exit 1
  fi
  if (( candidate_build <= installed_build )) && [[ "$allow_reinstall" != "1" ]]; then
    echo "Refusing to replace installed build $installed_build with build $candidate_build." >&2
    echo "Set MOMENT_MONITOR_ALLOW_REINSTALL=1 only for an intentional recovery or exact-build reinstall." >&2
    exit 1
  fi
fi

osascript -e 'tell application id "com.timyeou.momentmonitor" to quit' >/dev/null 2>&1 || true
for unused in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x MomentMonitor >/dev/null 2>&1 || break
  sleep 0.25
done
if pgrep -x MomentMonitor >/dev/null 2>&1; then
  echo "Moment Monitor is still running. Quit it, then rerun the installer." >&2
  exit 1
fi

if [[ -d "$destination" ]]; then
  mv "$destination" "$previous_app"
  backup_moved=true
fi

mv "$staged_app" "$destination"
backup_moved=false
codesign --verify --deep --strict "$destination"
open "$destination"

echo "Installed and launched: $destination"
