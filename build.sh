#!/bin/bash
# Build and run Piano Practice from the command line (one Xcode project, same code on iPhone, iPad and Mac).
#   ./build.sh mac           build + ad-hoc sign → build.noindex/Piano.app
#   ./build.sh mac-install   … and copy it to /Applications (or ~/Applications)
#   ./build.sh sim           build (Debug) + install + launch on the booted iOS simulator
#   ./build.sh device        build (Release) + install + launch on a paired device (DEVICE_NAME, default "iPad";
#                            a name prefix or the UDID). Needs DEVELOPMENT_TEAM set, e.g. DEVELOPMENT_TEAM=ABCDE12345
set -euo pipefail
BUNDLE_ID="${BUNDLE_ID:-com.example.pianopractice}"
TEAM=()
[ -n "${DEVELOPMENT_TEAM:-}" ] && TEAM=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID")

# xcodebuild, filtered; stops with the real error when it fails
xb() {
    local log; log="$(mktemp)"
    if ! xcodebuild "$@" >"$log" 2>&1; then
        grep -E "error|BUILD" "$log" | tail -5
        grep -q "errSecInternalComponent" "$log" && echo "signing failed: the login keychain is not reachable from" \
            "this session (sandboxed/remote shell). Run it from Terminal." >&2
        grep -q "Timed out waiting for all destinations" "$log" && echo "the device is still connecting:" \
            "run the same command again in a minute." >&2
        rm -f "$log"; exit 1
    fi
    grep -E "warning: .*Piano/|BUILD" "$log" || true
    rm -f "$log"
}
cd "$(dirname "$0")"
DD=build.noindex/dd
mkdir -p build.noindex   # ".noindex": build copies stay out of Spotlight/Launchpad
case "${1:-}" in
device|ipad)
    NAME="${DEVICE_NAME:-iPad}"
    UDID="$(xcrun devicectl list devices 2>/dev/null | awk -v n="$NAME" '(index($0, n) == 1 || $0 ~ "  " n " ") && /physical/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-/) print $i}' | head -1)"
    [ -n "$UDID" ] || { echo "error: no paired device named '$NAME' (xcrun devicectl list devices)" >&2; exit 1; }
    xb -project Piano.xcodeproj -scheme Piano -configuration Release -derivedDataPath "$DD" \
        -destination "platform=iOS,id=$UDID" -allowProvisioningUpdates "${TEAM[@]}" build
    APP="$DD/Build/Products/Release-iphoneos/Piano.app"
    [ -d "$APP" ] || exit 1
    xcrun devicectl device install app --device "$UDID" "$APP"
    xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" || \
        echo "not launched: unlock $NAME (first time: Settings › General › VPN & Device Management › Trust)"
    ;;
mac|mac-install)
    xb -project Piano.xcodeproj -scheme Piano -configuration Release -derivedDataPath "$DD" \
        -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
    rm -rf build.noindex/Piano.app
    ditto "$DD/Build/Products/Release/Piano.app" build.noindex/Piano.app
    codesign --force --deep --sign - build.noindex/Piano.app      # ad-hoc: runs on this Mac
    codesign --verify --strict build.noindex/Piano.app
    if [ "$1" = mac-install ]; then
        DEST=/Applications
        [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
        pkill -x Piano 2>/dev/null || true
        rm -rf "$DEST/Piano.app"
        ditto build.noindex/Piano.app "$DEST/Piano.app"
        rm -rf build.noindex/Piano.app
        echo "installed: $DEST/Piano.app"
    else
        echo "built: $(pwd)/build.noindex/Piano.app"
    fi
    ;;
sim)
    xb -project Piano.xcodeproj -scheme Piano -configuration Debug -derivedDataPath "$DD" \
        -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
    APP="$DD/Build/Products/Debug-iphonesimulator/Piano.app"
    [ -d "$APP" ] || exit 1
    xcrun simctl install booted "$APP"
    xcrun simctl launch --terminate-running-process booted "$BUNDLE_ID"
    ;;
*) echo "usage: $0 mac|mac-install|sim|device" >&2; exit 1 ;;
esac
