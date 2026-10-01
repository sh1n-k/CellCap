#!/bin/zsh
# helper를 내리고 macOS 충전 한도를 CellCap 개입 전 값으로 되돌린다.
# 앱 내장 helper는 보통 앱의 고급 정보 > Helper 제거로 지운다. 이 스크립트는 이전 방식(sudo 스크립트/pkg) 설치를
# 지우거나, 앱을 쓸 수 없을 때 helper를 강제로 내릴 때 쓴다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helper_common.sh"

require_root "BuildSupport/dev/uninstall_helper.sh"

stop_helper_and_remove_legacy_install
restore_charge_limit_baseline || echo "시스템 설정 > 배터리 > 충전 한도에서 값을 직접 확인하세요."

echo "helper 제거 완료"
echo "앱 내장 helper 등록 기록은 앱의 고급 정보 > Helper 제거 또는 앱 삭제로 정리됩니다."
