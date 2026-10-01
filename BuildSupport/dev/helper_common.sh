#!/bin/zsh

SERVICE_NAME="com.shin.cellcap.helper"
INSTALL_PATH="/Library/PrivilegedHelperTools/${SERVICE_NAME}"
PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
LOG_DIR="/Library/Logs/CellCap"
STDOUT_LOG="${LOG_DIR}/${SERVICE_NAME}.stdout.log"
STDERR_LOG="${LOG_DIR}/${SERVICE_NAME}.stderr.log"
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
