#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helper_common.sh"

require_root "BuildSupport/dev/uninstall_helper.sh"

launchctl bootout "system/${SERVICE_NAME}" >/dev/null 2>&1 || true
launchctl bootout system "${PLIST_PATH}" >/dev/null 2>&1 || true

rm -f "${PLIST_PATH}"
rm -f "${INSTALL_PATH}"
restore_charge_limit_baseline || echo "시스템 설정 > 배터리 > 충전 한도에서 값을 직접 확인하세요."

echo "helper 제거 완료"
