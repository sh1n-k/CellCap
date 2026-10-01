#!/bin/zsh

SERVICE_NAME="com.shin.cellcap.helper"
# helper는 앱 번들에 내장되어 SMAppService로 등록된다(CellCapHelperXPC.bundled* 상수와 같은 값).
HELPER_BUNDLE_PROGRAM_PATH="Contents/MacOS/CellCapHelper"
HELPER_BUNDLE_PLIST_PATH="Contents/Library/LaunchDaemons/${SERVICE_NAME}.plist"
# 아래는 sudo 스크립트/pkg로 설치하던 이전 방식 위치다(CellCapHelperXPC.legacy* 상수와 같은 값).
# 남아 있으면 앱 내장 helper 등록과 충돌하므로 제거에만 쓴다.
LEGACY_INSTALL_PATH="/Library/PrivilegedHelperTools/${SERVICE_NAME}"
LEGACY_PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
LEGACY_LOG_DIR="/Library/Logs/CellCap"
# CellCapHelperXPC.chargeLimitBaselinePath와 같은 값을 유지한다.
CHARGE_LIMIT_BASELINE_PATH="/Library/Application Support/CellCap/charge-limit-baseline.plist"
# helper가 바꾸는 macOS 충전 한도 설정(PowerUIAgent root 도메인)과 변경 알림.
MCL_PREFS_DOMAIN="/var/root/Library/Preferences/com.apple.smartcharging.topoffprotection"
MCL_LIMIT_KEY="mclLimitValue"
MCL_CHANGE_NOTIFICATION="com.apple.smartcharging.defaultschanged"

require_root() {
  local script_path="${1:-$0}"

  if [[ "${EUID}" -ne 0 ]]; then
    echo "root 권한이 필요합니다. sudo ${script_path} 로 다시 실행하세요."
    exit 1
  fi
}

# helper가 처음 개입하기 전의 macOS 충전 한도로 되돌린다. helper를 내린 뒤 호출해야 다시 덮어쓰이지 않는다.
restore_charge_limit_baseline() {
  if [[ ! -f "${CHARGE_LIMIT_BASELINE_PATH}" ]]; then
    return 0
  fi

  local baseline_limit
  baseline_limit="$(plutil -extract "${MCL_LIMIT_KEY}" raw -o - "${CHARGE_LIMIT_BASELINE_PATH}" 2>/dev/null || true)"
  if [[ "${baseline_limit}" == <-> ]]; then
    # 호출부가 `|| true`로 감싸면 set -e가 꺼지므로 실패를 직접 확인하고, 실패 시 baseline을 남겨 재시도할 수 있게 한다.
    if ! defaults write "${MCL_PREFS_DOMAIN}" "${MCL_LIMIT_KEY}" -int "${baseline_limit}" \
      || ! notifyutil -p "${MCL_CHANGE_NOTIFICATION}"; then
      echo "macOS 충전 한도 복원에 실패했습니다. baseline 보관: ${CHARGE_LIMIT_BASELINE_PATH}"
      return 1
    fi
    echo "macOS 충전 한도를 ${baseline_limit}%로 복원했습니다."
  fi

  rm -f "${CHARGE_LIMIT_BASELINE_PATH}"
  rmdir "$(dirname "${CHARGE_LIMIT_BASELINE_PATH}")" 2>/dev/null || true
}

# helper launchd job을 내린다. 이전 방식 설치가 남아 있으면 파일까지 지운다.
# 충전 한도 복원보다 먼저 호출해야 helper가 복원값을 다시 덮어쓰지 않는다.
stop_helper_and_remove_legacy_install() {
  launchctl bootout "system/${SERVICE_NAME}" >/dev/null 2>&1 || true
  launchctl bootout system "${LEGACY_PLIST_PATH}" >/dev/null 2>&1 || true
  rm -f "${LEGACY_PLIST_PATH}" "${LEGACY_INSTALL_PATH}"
  rm -rf "${LEGACY_LOG_DIR}"
}
