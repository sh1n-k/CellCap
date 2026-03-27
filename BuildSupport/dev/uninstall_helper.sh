#!/bin/zsh
set -euo pipefail

SERVICE_NAME="com.shin.cellcap.helper"
INSTALL_PATH="/Library/PrivilegedHelperTools/${SERVICE_NAME}"
PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"

if [[ "${EUID}" -ne 0 ]]; then
  echo "root 권한이 필요합니다. sudo BuildSupport/dev/uninstall_helper.sh 로 다시 실행하세요."
  exit 1
fi

launchctl bootout "system/${SERVICE_NAME}" >/dev/null 2>&1 || true
launchctl bootout system "${PLIST_PATH}" >/dev/null 2>&1 || true

rm -f "${PLIST_PATH}"
rm -f "${INSTALL_PATH}"

echo "helper 제거 완료"
