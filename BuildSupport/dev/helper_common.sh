#!/bin/zsh

SERVICE_NAME="com.shin.cellcap.helper"
INSTALL_PATH="/Library/PrivilegedHelperTools/${SERVICE_NAME}"
PLIST_PATH="/Library/LaunchDaemons/${SERVICE_NAME}.plist"
LOG_DIR="/Library/Logs/CellCap"
STDOUT_LOG="${LOG_DIR}/${SERVICE_NAME}.stdout.log"
STDERR_LOG="${LOG_DIR}/${SERVICE_NAME}.stderr.log"

require_root() {
  local script_path="${1:-$0}"

  if [[ "${EUID}" -ne 0 ]]; then
    echo "root 권한이 필요합니다. sudo ${script_path} 로 다시 실행하세요."
    exit 1
  fi
}
