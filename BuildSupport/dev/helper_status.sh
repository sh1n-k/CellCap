#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helper_common.sh"
source "${SCRIPT_DIR}/../release/release_common.sh"

echo "CellCap helper 상태"
echo "  앱 내장 helper: $([[ -x "${APP_INSTALL_PATH}/${HELPER_BUNDLE_PROGRAM_PATH}" ]] && echo "present" || echo "missing") (${APP_INSTALL_PATH}/${HELPER_BUNDLE_PROGRAM_PATH})"
if [[ -e "${LEGACY_INSTALL_PATH}" || -e "${LEGACY_PLIST_PATH}" ]]; then
  echo "  이전 방식 설치가 남아 있습니다: ${LEGACY_INSTALL_PATH}, ${LEGACY_PLIST_PATH}"
  echo "  sudo BuildSupport/dev/uninstall_helper.sh 로 제거하세요."
fi
if [[ -f "${CHARGE_LIMIT_BASELINE_PATH}" ]]; then
  echo "  CellCap이 충전 한도를 관리 중입니다(원래 값 보관: ${CHARGE_LIMIT_BASELINE_PATH})."
fi

echo
echo "launchctl print system/${SERVICE_NAME}"
if ! /bin/launchctl print "system/${SERVICE_NAME}" 2>&1 | grep -E "state =|pid =|last exit|program identifier|parent bundle"; then
  echo "  launchd에서 helper를 찾지 못했습니다. 앱의 고급 정보에서 helper를 설치하세요."
fi

echo
echo "백그라운드 항목(BTM)"
sfltool dumpbtm 2>/dev/null | grep -B2 -A6 "16\.${SERVICE_NAME}" | grep -E "Name:|Disposition:|URL:" | sort -u || echo "  항목 없음"

echo
echo "최근 helper 로그: /usr/bin/log show --last 10m --predicate 'process == \"${HELPER_PRODUCT_NAME}\"'"
