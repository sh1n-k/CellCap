#!/bin/zsh
# helper를 포함한 CellCap.app을 고정 서명 인증서로 빌드해 /Applications에 설치하고 다시 연다.
# helper 등록/승인은 앱 설정 화면에서 한다. 이 스크립트는 root 권한이 필요 없다.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/BuildSupport/dev/helper_common.sh"
source "${ROOT_DIR}/BuildSupport/release/release_common.sh"

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/.build/xcode}"
BUILT_APP="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_BUNDLE_NAME}"
INSTALL_APP="${INSTALL_APP:-${APP_INSTALL_PATH}}"
INSTALL_PARENT="$(dirname "${INSTALL_APP}")"
# 서명 인증서가 바뀌면 macOS가 helper 실행을 거부(Launch Constraint Violation)하고 재승인을 요구한다.
# 그래서 ad-hoc으로 대체하지 않고 고정 인증서가 없으면 중단한다.
SIGN_IDENTITY="${SIGN_IDENTITY:-CellCap Dev}"
SIGN_IDENTITY_MARKER="${DERIVED_DATA_PATH}/.cellcap-sign-identity"
STAGING_DIR=""
BACKUP_DIR=""
REPLACEMENT_STARTED=0
HAD_INSTALLED_APP=0

log() {
  printf "\n==> %s\n" "$1"
}

cleanup_install_state() {
  local exit_code=$?
  trap - EXIT

  if (( exit_code != 0 && REPLACEMENT_STARTED == 1 )); then
    # 교체 구간(백업 이동 ~ 새 앱 이동) 안에서 실패한 경우에만 여기로 온다.
    log "설치 실패: 이전 앱으로 되돌립니다"
    if (( HAD_INSTALLED_APP == 1 )) && [[ -d "${BACKUP_DIR}/${APP_BUNDLE_NAME}" ]]; then
      rm -rf "${INSTALL_APP}"
      if ! mv "${BACKUP_DIR}/${APP_BUNDLE_NAME}" "${INSTALL_APP}"; then
        echo "이전 앱 복원에 실패했습니다. 백업: ${BACKUP_DIR}" >&2
        BACKUP_DIR=""
      fi
    fi
  fi

  [[ -n "${STAGING_DIR}" ]] && rm -rf "${STAGING_DIR}"
  [[ -n "${BACKUP_DIR}" ]] && rm -rf "${BACKUP_DIR}"
  exit "${exit_code}"
}

trap cleanup_install_state EXIT

require_sign_identity() {
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"${SIGN_IDENTITY}\""; then
    echo "코드 서명 인증서 '${SIGN_IDENTITY}'를 찾지 못했습니다." >&2
    echo "키체인 접근 > 인증서 지원 > 인증서 생성에서 자체 서명 루트, 코드 서명 유형으로 만드세요." >&2
    exit 1
  fi
}

verify_app_bundle() {
  local app_bundle="$1"
  local helper_binary="${app_bundle}/Contents/MacOS/${HELPER_PRODUCT_NAME}"
  local helper_plist="${app_bundle}/Contents/Library/LaunchDaemons/${SERVICE_NAME}.plist"

  [[ -x "${helper_binary}" ]] || { echo "번들에 helper가 없습니다: ${helper_binary}" >&2; exit 1; }
  [[ -f "${helper_plist}" ]] || { echo "번들에 LaunchDaemon plist가 없습니다: ${helper_plist}" >&2; exit 1; }
  plutil -lint "${helper_plist}" >/dev/null
  codesign --verify --deep --strict "${app_bundle}"

  # 증분 빌드는 helper를 다시 서명하지 않을 수 있으므로 helper 서명 주체를 직접 확인한다.
  # grep -q가 먼저 끝나면 pipefail에서 codesign SIGPIPE가 실패로 잡히므로 출력을 먼저 받아 둔다.
  local helper_signature
  helper_signature="$(codesign -dvv "${helper_binary}" 2>&1)"
  if [[ "${helper_signature}" != *$'\n'"Authority=${SIGN_IDENTITY}"$'\n'* ]]; then
    echo "helper가 '${SIGN_IDENTITY}'로 서명되지 않았습니다: ${helper_binary}" >&2
    exit 1
  fi
}

quit_running_app() {
  pgrep -x "${APP_PRODUCT_NAME}" >/dev/null 2>&1 || return 0

  log "실행 중인 ${APP_PRODUCT_NAME} 종료"
  osascript -e "tell application id \"${APP_BUNDLE_IDENTIFIER}\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x "${APP_PRODUCT_NAME}" >/dev/null 2>&1 || return 0
    sleep 0.25
  done

  pkill -TERM -x "${APP_PRODUCT_NAME}" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x "${APP_PRODUCT_NAME}" >/dev/null 2>&1 || return 0
    sleep 0.25
  done

  echo "${APP_PRODUCT_NAME}이 종료되지 않아 설치를 중단합니다." >&2
  exit 1
}

require_sign_identity

build_action=(build)
if [[ "$(cat "${SIGN_IDENTITY_MARKER}" 2>/dev/null || true)" != "${SIGN_IDENTITY}" ]]; then
  build_action=(clean build)
fi

log "${APP_BUNDLE_NAME} 빌드 (${CONFIGURATION}, 서명: ${SIGN_IDENTITY}, ${build_action[*]})"
BUILD_LOG="$(mktemp -t cellcap-xcodebuild)"
# ENABLE_DEBUG_DYLIB=NO: Team ID가 없는 자체 서명에서는 별도 debug dylib 로딩이 거부될 수 있다.
xcodebuild \
  -project "${ROOT_DIR}/CellCap.xcodeproj" \
  -scheme AppUI \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="${SIGN_IDENTITY}" \
  DEVELOPMENT_TEAM= \
  ENABLE_DEBUG_DYLIB=NO \
  "${build_action[@]}" > "${BUILD_LOG}" 2>&1 || {
    grep -E "error:" "${BUILD_LOG}" | sort -u >&2 || true
    echo "xcodebuild 실패. 전체 로그: ${BUILD_LOG}" >&2
    exit 1
  }
rm -f "${BUILD_LOG}"

[[ -d "${BUILT_APP}" ]] || { echo "빌드된 앱을 찾지 못했습니다: ${BUILT_APP}" >&2; exit 1; }
verify_app_bundle "${BUILT_APP}"
print -r -- "${SIGN_IDENTITY}" > "${SIGN_IDENTITY_MARKER}"

STAGING_DIR="$(mktemp -d "${INSTALL_PARENT}/.${APP_PRODUCT_NAME}.install.XXXXXX")"
ditto "${BUILT_APP}" "${STAGING_DIR}/${APP_BUNDLE_NAME}"
verify_app_bundle "${STAGING_DIR}/${APP_BUNDLE_NAME}"

quit_running_app

log "${INSTALL_APP}에 설치"
REPLACEMENT_STARTED=1
if [[ -e "${INSTALL_APP}" ]]; then
  HAD_INSTALLED_APP=1
  BACKUP_DIR="$(mktemp -d "${INSTALL_PARENT}/.${APP_PRODUCT_NAME}.backup.XXXXXX")"
  mv "${INSTALL_APP}" "${BACKUP_DIR}/${APP_BUNDLE_NAME}"
fi
mv "${STAGING_DIR}/${APP_BUNDLE_NAME}" "${INSTALL_APP}"
REPLACEMENT_STARTED=0

log "${INSTALL_APP} 실행"
# 직전 종료와 교체 직후에는 LaunchServices가 -600으로 실패할 수 있어 몇 번 다시 시도한다.
for attempt in {1..3}; do
  open "${INSTALL_APP}" && break
  (( attempt == 3 )) && { echo "${INSTALL_APP}을 열지 못했습니다. 직접 실행하세요." >&2; exit 1; }
  sleep 1
done

cat <<EOF

완료.
실행 중인 helper는 이전 바이너리를 계속 씁니다. helper 코드나 LaunchDaemon plist가 바뀌었으면
메뉴의 고급 정보에서 '다시 설치'를 누르세요. 자체 서명 helper는 바이너리가 바뀌면
시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램에서 CellCap을 다시 허용해야 합니다.
EOF
