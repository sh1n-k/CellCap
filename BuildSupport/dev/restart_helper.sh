#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/BuildSupport/dev/helper_common.sh"

require_root "BuildSupport/dev/restart_helper.sh"

if [[ ! -f "${PLIST_PATH}" ]]; then
  echo "설치된 launchd plist가 없습니다: ${PLIST_PATH}"
  exit 1
fi

launchctl kickstart -k "system/${SERVICE_NAME}" >/dev/null 2>&1 || {
  launchctl bootout "system/${SERVICE_NAME}" >/dev/null 2>&1 || true
  launchctl bootstrap system "${PLIST_PATH}"
  launchctl kickstart -k "system/${SERVICE_NAME}"
}

echo "helper 재시작 완료"
"${ROOT_DIR}/BuildSupport/dev/helper_status.sh"
