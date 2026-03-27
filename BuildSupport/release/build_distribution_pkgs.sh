#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "${ROOT_DIR}/BuildSupport/dev/helper_common.sh"
source "${ROOT_DIR}/BuildSupport/release/release_common.sh"

PROJECT_PATH="${ROOT_DIR}/CellCap.xcodeproj"
DERIVED_DATA_PATH="${ROOT_DIR}/.build/xcode-release"
OUTPUT_DIR="${ROOT_DIR}/dist"
CONFIGURATION="Release"
VERSION=""
SKIP_BUILD=0
SKIP_PROJECT_GENERATION=0

usage() {
  cat <<'EOF'
사용법:
  BuildSupport/release/build_distribution_pkgs.sh --version <버전> [옵션]

옵션:
  --version <버전>         pkg 버전 문자열. 예: 0.1.0
  --output-dir <경로>      산출물 출력 디렉터리. 기본값: ./dist
  --derived-data <경로>    xcodebuild derived data 경로. 기본값: ./.build/xcode-release
  --configuration <이름>   Xcode 빌드 설정. 기본값: Release
  --skip-build             기존 빌드 산출물을 재사용하고 xcodebuild를 건너뜀
  --skip-project-generation
                          xcodeproj 재생성을 건너뜀
  --help                   도움말 출력
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_PATH="${2:-}"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --skip-project-generation)
      SKIP_PROJECT_GENERATION=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "알 수 없는 옵션입니다: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  echo "--version 값이 필요합니다."
  usage
  exit 1
fi

APP_BUNDLE="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_BUNDLE_NAME}"
HELPER_BINARY=""

build_target() {
  local scheme="$1"

  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${scheme}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build
}

build_helper_binary() {
  local swift_configuration

  swift_configuration="$(echo "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')"
  case "${swift_configuration}" in
    release|debug)
      ;;
    *)
      echo "swift build는 ${CONFIGURATION} 설정을 지원하지 않습니다. Debug 또는 Release만 사용하세요."
      exit 1
      ;;
  esac

  swift build -c "${swift_configuration}" --product "${HELPER_PRODUCT_NAME}"
}

find_helper_binary() {
  local -a candidates=(
    "${ROOT_DIR}/.build/arm64-apple-macosx/${CONFIGURATION:l}/${HELPER_PRODUCT_NAME}"
    "${ROOT_DIR}/.build/${CONFIGURATION:l}/${HELPER_PRODUCT_NAME}"
    "${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${HELPER_PRODUCT_NAME}"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "${candidate}" ]]; then
      echo "${candidate}"
      return 0
    fi
  done

  candidate="$(find "${ROOT_DIR}/.build" -type f -path "*/${CONFIGURATION:l}/${HELPER_PRODUCT_NAME}" 2>/dev/null | head -n 1 || true)"
  if [[ -n "${candidate}" && -x "${candidate}" ]]; then
    echo "${candidate}"
    return 0
  fi

  return 1
}

regenerate_project() {
  ruby "${ROOT_DIR}/BuildSupport/generate_xcodeproj.rb"
}

prepare_pkg_scripts() {
  local template_dir="$1"
  local destination_dir="$2"

  mkdir -p "${destination_dir}"
  cp -X "${ROOT_DIR}/BuildSupport/dev/helper_common.sh" "${destination_dir}/helper_common.sh"
  cp -X "${ROOT_DIR}/BuildSupport/release/release_common.sh" "${destination_dir}/release_common.sh"
  cp -X "${template_dir}"/* "${destination_dir}/"
  chmod 755 "${destination_dir}"/*
}

create_component_plist() {
  local root_path="$1"
  local plist_path="$2"

  pkgbuild --analyze --root "${root_path}" "${plist_path}" >/dev/null

  /usr/libexec/PlistBuddy \
    -c "Set :0:BundleIsRelocatable false" \
    "${plist_path}"
}

render_launchd_plist() {
  local destination="$1"
  local template_path="${ROOT_DIR}/BuildSupport/dev/${SERVICE_NAME}.plist.template"

  if [[ ! -f "${template_path}" ]]; then
    echo "launchd plist 템플릿이 없습니다: ${template_path}"
    exit 1
  fi

  sed \
    -e "s#__HELPER_PATH__#${INSTALL_PATH}#g" \
    -e "s#__STDOUT_PATH__#${STDOUT_LOG}#g" \
    -e "s#__STDERR_PATH__#${STDERR_LOG}#g" \
    "${template_path}" > "${destination}"
}

create_staging_root() {
  local destination_root="$1"

  mkdir -p \
    "${destination_root}/Applications" \
    "${destination_root}/Library/PrivilegedHelperTools" \
    "${destination_root}/Library/LaunchDaemons"

  ditto --norsrc --noextattr --noqtn "${APP_BUNDLE}" "${destination_root}${APP_INSTALL_PATH}"
  install -m 755 "${HELPER_BINARY}" "${destination_root}${INSTALL_PATH}"
  render_launchd_plist "${destination_root}${PLIST_PATH}"
  chmod 644 "${destination_root}${PLIST_PATH}"

  xattr -cr "${destination_root}" >/dev/null 2>&1 || true
  find "${destination_root}" -name '._*' -delete
}

if (( ! SKIP_BUILD )); then
  if (( ! SKIP_PROJECT_GENERATION )); then
    regenerate_project
  fi

  if [[ ! -d "${PROJECT_PATH}" ]]; then
    echo "Xcode 프로젝트가 없습니다: ${PROJECT_PATH}"
    echo "먼저 ruby BuildSupport/generate_xcodeproj.rb 를 실행하세요."
    exit 1
  fi

  build_target "AppUI"
  build_helper_binary
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "앱 번들을 찾지 못했습니다: ${APP_BUNDLE}"
  exit 1
fi

HELPER_BINARY="$(find_helper_binary)" || {
  echo "helper 바이너리를 찾지 못했습니다."
  exit 1
}

if [[ ! -x "${HELPER_BINARY}" ]]; then
  echo "helper 바이너리를 찾지 못했습니다: ${HELPER_BINARY}"
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cellcap-pkg.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

INSTALL_ROOT="${WORK_DIR}/install-root"
INSTALL_SCRIPTS_DIR="${WORK_DIR}/install-scripts"
UNINSTALL_SCRIPTS_DIR="${WORK_DIR}/uninstall-scripts"
COMPONENT_PLIST_PATH="${WORK_DIR}/components.plist"

create_staging_root "${INSTALL_ROOT}"
create_component_plist "${INSTALL_ROOT}" "${COMPONENT_PLIST_PATH}"
prepare_pkg_scripts "${ROOT_DIR}/BuildSupport/release/templates/install" "${INSTALL_SCRIPTS_DIR}"
prepare_pkg_scripts "${ROOT_DIR}/BuildSupport/release/templates/uninstall" "${UNINSTALL_SCRIPTS_DIR}"
xattr -cr "${INSTALL_SCRIPTS_DIR}" "${UNINSTALL_SCRIPTS_DIR}" >/dev/null 2>&1 || true
find "${INSTALL_SCRIPTS_DIR}" "${UNINSTALL_SCRIPTS_DIR}" -name '._*' -delete

mkdir -p "${OUTPUT_DIR}"

INSTALL_PKG_PATH="${OUTPUT_DIR}/${APP_PRODUCT_NAME}-${VERSION}.pkg"
UNINSTALL_PKG_PATH="${OUTPUT_DIR}/${APP_PRODUCT_NAME}-Uninstall-${VERSION}.pkg"

COPY_EXTENDED_ATTRIBUTES_DISABLE=1 COPYFILE_DISABLE=1 pkgbuild \
  --root "${INSTALL_ROOT}" \
  --component-plist "${COMPONENT_PLIST_PATH}" \
  --scripts "${INSTALL_SCRIPTS_DIR}" \
  --identifier "${INSTALL_PACKAGE_IDENTIFIER}" \
  --version "${VERSION}" \
  "${INSTALL_PKG_PATH}"

COPY_EXTENDED_ATTRIBUTES_DISABLE=1 COPYFILE_DISABLE=1 pkgbuild \
  --nopayload \
  --scripts "${UNINSTALL_SCRIPTS_DIR}" \
  --identifier "${UNINSTALL_PACKAGE_IDENTIFIER}" \
  --version "${VERSION}" \
  "${UNINSTALL_PKG_PATH}"

shasum -a 256 "${INSTALL_PKG_PATH}" > "${INSTALL_PKG_PATH}.sha256"
shasum -a 256 "${UNINSTALL_PKG_PATH}" > "${UNINSTALL_PKG_PATH}.sha256"

echo "배포용 pkg 생성 완료"
echo "  install:   ${INSTALL_PKG_PATH}"
echo "  uninstall: ${UNINSTALL_PKG_PATH}"
echo "  checksums: ${INSTALL_PKG_PATH}.sha256"
echo "             ${UNINSTALL_PKG_PATH}.sha256"
