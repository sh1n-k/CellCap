#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SERVICE_NAME="com.shin.cellcap.helper"
INSTALL_PATH="/Library/PrivilegedHelperTools/${SERVICE_NAME}"
PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
LOG_DIR="/Library/Logs/CellCap"
STDOUT_LOG="${LOG_DIR}/${SERVICE_NAME}.stdout.log"
STDERR_LOG="${LOG_DIR}/${SERVICE_NAME}.stderr.log"
TEMPLATE_PATH="${ROOT_DIR}/BuildSupport/dev/${SERVICE_NAME}.plist.template"

if [[ "${EUID}" -ne 0 ]]; then
  echo "root 권한이 필요합니다. sudo BuildSupport/dev/install_helper.sh 로 다시 실행하세요."
  exit 1
fi

find_helper_binary() {
  if [[ $# -gt 0 && -n "$1" && -x "$1" ]]; then
    echo "$1"
    return 0
  fi

  if [[ -n "${CELLCAP_HELPER_BINARY:-}" && -x "${CELLCAP_HELPER_BINARY}" ]]; then
    echo "${CELLCAP_HELPER_BINARY}"
    return 0
  fi

  local -a candidates=(
    "${ROOT_DIR}/.build/arm64-apple-macosx/debug/CellCapHelper"
    "${ROOT_DIR}/.build/debug/CellCapHelper"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  candidate="$(find "${ROOT_DIR}/.build" -type f -name CellCapHelper 2>/dev/null | head -n 1 || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi

  return 1
}

HELPER_BINARY="$(find_helper_binary "${1:-}")" || {
  echo "CellCapHelper 바이너리를 찾지 못했습니다."
  echo "공식 개발 경로는 swift build 로 생성한 SwiftPM 산출물입니다."
  echo "Xcode 산출물을 쓰려면 CELLCAP_HELPER_BINARY 또는 첫 번째 인자로 helper 경로를 직접 지정하세요."
  exit 1
}

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  echo "launchd plist 템플릿이 없습니다: ${TEMPLATE_PATH}"
  exit 1
fi

mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons "${LOG_DIR}"
install -m 755 "${HELPER_BINARY}" "${INSTALL_PATH}"
chown root:wheel "${INSTALL_PATH}"

TMP_PLIST="$(mktemp "/tmp/${SERVICE_NAME}.XXXXXX.plist")"
sed \
  -e "s#__HELPER_PATH__#${INSTALL_PATH}#g" \
  -e "s#__STDOUT_PATH__#${STDOUT_LOG}#g" \
  -e "s#__STDERR_PATH__#${STDERR_LOG}#g" \
  "${TEMPLATE_PATH}" > "${TMP_PLIST}"

install -m 644 "${TMP_PLIST}" "${PLIST_PATH}"
chown root:wheel "${PLIST_PATH}"
rm -f "${TMP_PLIST}"

launchctl bootout "system/${SERVICE_NAME}" >/dev/null 2>&1 || true
launchctl bootout system "${PLIST_PATH}" >/dev/null 2>&1 || true
launchctl bootstrap system "${PLIST_PATH}"
launchctl kickstart -k "system/${SERVICE_NAME}"

echo "helper 설치 완료"
echo "  binary: ${INSTALL_PATH}"
echo "  plist:  ${PLIST_PATH}"
echo "  stdout: ${STDOUT_LOG}"
echo "  stderr: ${STDERR_LOG}"
echo
"${ROOT_DIR}/BuildSupport/dev/helper_status.sh"
