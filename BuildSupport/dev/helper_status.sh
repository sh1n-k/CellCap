#!/bin/zsh
set -euo pipefail

SERVICE_NAME="com.shin.cellcap.helper"
INSTALL_PATH="/Library/PrivilegedHelperTools/${SERVICE_NAME}"
PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
STDOUT_LOG="/Library/Logs/CellCap/${SERVICE_NAME}.stdout.log"
STDERR_LOG="/Library/Logs/CellCap/${SERVICE_NAME}.stderr.log"

echo "CellCap helper 상태"
echo "  binary: $([[ -x "${INSTALL_PATH}" ]] && echo "present" || echo "missing") (${INSTALL_PATH})"
echo "  plist:  $([[ -f "${PLIST_PATH}" ]] && echo "present" || echo "missing") (${PLIST_PATH})"
echo
echo "launchctl print system/${SERVICE_NAME}"
if /bin/launchctl print "system/${SERVICE_NAME}" 2>&1; then
  :
else
  echo
  echo "launchctl 출력에서 helper를 찾지 못했습니다."
fi

echo
echo "로그 경로"
echo "  stdout: ${STDOUT_LOG}"
echo "  stderr: ${STDERR_LOG}"
