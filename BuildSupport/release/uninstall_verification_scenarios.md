# CellCap Uninstall Verification Scenarios

이 문서는 언인스톨러 pkg의 실기 검증 절차를 고정한다.
사람이 직접 확인하는 편이 더 정확한 macOS 권한, 로그인 항목, 시스템 설정 반영 여부는 아래 시나리오로 검증한다.

## 준비

```bash
VERSION=0.0.0-uninstall-test
DIST_DIR=dist-uninstall-verification

BuildSupport/release/build_distribution_pkgs.sh \
  --version "${VERSION}" \
  --output-dir "${DIST_DIR}" \
  --derived-data .build/xcode-release-uninstall-verification

INSTALL_PKG="${DIST_DIR}/CellCap-${VERSION}.pkg"
UNINSTALL_PKG="${DIST_DIR}/CellCap-Uninstall-${VERSION}.pkg"
```

## 기준 상태 기록

```bash
pkgutil --pkgs | grep -E '^com\.shin\.cellcap(\.pkg|\.uninstall)$' || true
launchctl print system/com.shin.cellcap.helper >/tmp/cellcap-helper-before.txt 2>&1 || true
defaults read com.shin.cellcap.app >/tmp/cellcap-defaults-before.txt 2>&1 || true
```

## 시나리오 1: 설치 후 제거

```bash
sudo installer -pkg "${INSTALL_PKG}" -target /

test -d /Applications/CellCap.app
test -f /Library/LaunchDaemons/com.shin.cellcap.helper.plist
test -x /Library/PrivilegedHelperTools/com.shin.cellcap.helper
test -d /Library/Logs/CellCap
pkgutil --pkgs | grep '^com\.shin\.cellcap\.pkg$'

open /Applications/CellCap.app
```

앱에서 로그인 자동 실행을 켠 상태로 둔다.

```bash
defaults write com.shin.cellcap.app com.shin.cellcap.charge-policy -data 7b7d
defaults write com.shin.cellcap.app com.shin.cellcap.launch-at-login-enabled -bool true

sudo installer -pkg "${UNINSTALL_PKG}" -target /
sleep 5
```

기대 결과:

```bash
test ! -e /Library/LaunchDaemons/com.shin.cellcap.helper.plist
test ! -e /Library/PrivilegedHelperTools/com.shin.cellcap.helper
test ! -e /Applications/CellCap.app
test ! -e /Library/Logs/CellCap
! pkgutil --pkgs | grep -q '^com\.shin\.cellcap\.pkg$'
! pkgutil --pkgs | grep -q '^com\.shin\.cellcap\.uninstall$'
! defaults read com.shin.cellcap.app >/dev/null 2>&1
! launchctl print system/com.shin.cellcap.helper >/dev/null 2>&1
```

시스템 설정의 로그인 항목 목록에서 CellCap이 남아 있지 않아야 한다.

## 시나리오 2: idempotency

이미 제거된 상태에서 같은 언인스톨러를 다시 실행한다.

```bash
sudo installer -pkg "${UNINSTALL_PKG}" -target /
sleep 5

test ! -e /Library/LaunchDaemons/com.shin.cellcap.helper.plist
test ! -e /Library/PrivilegedHelperTools/com.shin.cellcap.helper
test ! -e /Applications/CellCap.app
test ! -e /Library/Logs/CellCap
! pkgutil --pkgs | grep -q '^com\.shin\.cellcap\.pkg$'
! pkgutil --pkgs | grep -q '^com\.shin\.cellcap\.uninstall$'
! defaults read com.shin.cellcap.app >/dev/null 2>&1
```

언인스톨러가 실패 없이 종료되어야 한다.

## 시나리오 3: 일반 사용자 Applications 위치

`/Applications` 외 일반 설치 위치에 안전하게 식별 가능한 CellCap 복사본이 있을 때 제거되는지 확인한다.

```bash
sudo installer -pkg "${INSTALL_PKG}" -target /
mkdir -p "${HOME}/Applications"
ditto /Applications/CellCap.app "${HOME}/Applications/CellCap.app"

plutil -extract CFBundleIdentifier raw -o - \
  "${HOME}/Applications/CellCap.app/Contents/Info.plist"

sudo installer -pkg "${UNINSTALL_PKG}" -target /
sleep 5

test ! -e "${HOME}/Applications/CellCap.app"
test ! -e /Applications/CellCap.app
```

`CFBundleIdentifier`가 `com.shin.cellcap.app`인 복사본만 삭제되어야 한다.

## 시나리오 4: 타 앱 보호

이름만 같은 타 앱 또는 bundle id가 다른 앱은 삭제하지 않아야 한다.

```bash
mkdir -p "${HOME}/Applications/CellCap.app/Contents"
cat > "${HOME}/Applications/CellCap.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.example.not-cellcap</string>
</dict>
</plist>
EOF

sudo installer -pkg "${UNINSTALL_PKG}" -target /

test -d "${HOME}/Applications/CellCap.app"
rm -rf "${HOME}/Applications/CellCap.app"
```

## 시나리오 5: 로그인 항목 반영

1. CellCap을 설치하고 실행한다.
2. 앱에서 로그인 자동 실행을 켠다.
3. 시스템 설정의 로그인 항목에 CellCap이 보이는지 확인한다.
4. 언인스톨러 pkg를 실행한다.
5. 시스템 설정을 다시 열어 CellCap 항목이 사라졌는지 확인한다.

보조 확인:

```bash
sfltool dumpbtm | grep -i CellCap || true
```

`sfltool` 출력 형식은 macOS 버전에 따라 달라질 수 있으므로, 최종 판정은 시스템 설정 UI와 앱 재부팅 후 동작을 함께 본다.

## 최종 판정 체크리스트

아래 항목을 모두 통과해야 언인스톨러 실기 검증을 완료로 판정한다.

| 항목 | 확인 방법 | 통과 기준 |
| --- | --- | --- |
| helper launchd 등록 | `launchctl print system/com.shin.cellcap.helper` | 명령이 실패하거나 서비스를 찾지 못한다. |
| helper plist | `test ! -e /Library/LaunchDaemons/com.shin.cellcap.helper.plist` | 파일이 없다. |
| helper binary | `test ! -e /Library/PrivilegedHelperTools/com.shin.cellcap.helper` | 파일이 없다. |
| 기본 앱 위치 | `test ! -e /Applications/CellCap.app` | 앱 번들이 없다. |
| helper 로그 | `test ! -e /Library/Logs/CellCap` | 로그 디렉터리가 없다. |
| install receipt | `pkgutil --pkgs \| grep '^com\.shin\.cellcap\.pkg$'` | 매칭 결과가 없다. |
| uninstall receipt | `pkgutil --pkgs \| grep '^com\.shin\.cellcap\.uninstall$'` | 매칭 결과가 없다. |
| UserDefaults | `defaults read com.shin.cellcap.app` | domain을 읽을 수 없다. |
| 로그인 항목 | 시스템 설정, `sfltool dumpbtm` 보조 확인 | CellCap 로그인 항목이 없다. |
| 일반 사용자 앱 위치 | `test ! -e "${HOME}/Applications/CellCap.app"` | bundle id가 CellCap인 복사본은 없다. |
| 타 앱 보호 | bundle id가 다른 `${HOME}/Applications/CellCap.app` fixture | 삭제되지 않는다. |
| idempotency | 제거 완료 후 같은 uninstall pkg 재실행 | 실패 없이 종료되고 제거 완료 상태가 유지된다. |

검증 환경에서 `sudo` 입력이 필요하면 사람이 직접 입력한다. 자동화 환경에서는 `sudo -n true`가 성공하는지 먼저 확인한다.
