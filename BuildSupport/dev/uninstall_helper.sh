#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helper_common.sh"

require_root "BuildSupport/dev/uninstall_helper.sh"

launchctl bootout "system/${SERVICE_NAME}" >/dev/null 2>&1 || true
launchctl bootout system "${PLIST_PATH}" >/dev/null 2>&1 || true

rm -f "${PLIST_PATH}"
rm -f "${INSTALL_PATH}"

echo "helper 제거 완료"
