#!/bin/bash
# The App Store's creative assets for iOS 27, drawn by the app's own globe offscreen
# (`CreativeStudio`, Debug only, `-NomadedDebugCreative YES`) in the simulator:
#   header.mp4      product page header, 21:9, 3840×1646, a 20 s loop, H.264, no sound
#   header.png      the same header as a picture (the video's first frame)
#   search-en.png   search results, 3:2, 3840×2560, English
#   search-ru.png   the same in Russian
# Everything lands in output/creative/. Takes about 5 minutes, most of it the video. See README.md.
#
#   Tools/Screenshots/creative.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

OS="18.6"
DEVICE="iPhone 16 Pro Max"
BUNDLE=com.leonkazaryan.nomaded
OUT=Tools/Screenshots/output/creative
BUILD="${TMPDIR:-/tmp}/nomaded-screenshots"

UDID=$(xcrun simctl list devices available | awk -v os="-- iOS $OS --" -v name="    $DEVICE (" '
    /^-- / { inside = ($0 == os) }
    inside && index($0, name) == 1 { match($0, /\([0-9A-F-]+\)/); print substr($0, RSTART + 1, RLENGTH - 2); exit }
')
[ -n "$UDID" ] || { echo "No $DEVICE simulator on iOS $OS. Add it in Xcode → Window → Devices and Simulators."; exit 1; }

echo "Building for $DEVICE (iOS $OS)…"
xcodebuild -project Nomaded.xcodeproj -scheme Nomaded -destination "platform=iOS Simulator,id=$UDID,arch=arm64" \
    -derivedDataPath "$BUILD" -quiet build 2>&1 | grep -v appintentsmetadataprocessor || true

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$BUILD/Build/Products/Debug-iphonesimulator/Nomaded.app"
DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
mkdir -p "$OUT"

render() { # language, region, whether to make the header too
    local language=$1 region=$2 header=$3
    rm -rf "$DATA/tmp/Creative"
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -NomadedDebugCreative YES \
        -NomadedDebugCreativeHeader "$header" -AppleLanguages "($language)" -AppleLocale "${language}_$region" >/dev/null
    # The studio writes done.txt last; the video takes a few minutes.
    for _ in $(seq 1 600); do
        [ -f "$DATA/tmp/Creative/done.txt" ] && break
        sleep 2
    done
    local result
    result=$(cat "$DATA/tmp/Creative/done.txt" 2>/dev/null || echo "Timed out")
    echo "  $language: $result"
    [[ $result == Done* ]] || exit 1
    cp "$DATA/tmp/Creative/"*.png "$OUT/"
    if [ "$header" = YES ]; then cp "$DATA/tmp/Creative/header.mp4" "$OUT/"; fi
}

echo "Drawing (the header video takes a few minutes)…"
render en US YES
render ru RU NO
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "Done: $OUT"
ls -lh "$OUT"
