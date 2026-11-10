#!/bin/bash
# App Store screenshots: the app's own scenes, driven by the DEBUG launch arguments, on the
# iPhone 16 Pro Max simulator (6.9", 1320×2868), or with `ipad` on the iPad Pro 13-inch
# (2064×2752, held upright). iOS 18.6 on purpose: the Xcode 26.3 simulator for iOS 26 draws
# flags as "?". Raw shots go to output/raw/<language>/ (output/ipad/raw/… for the iPad),
# compose.swift then adds the captions. See README.md.
#
#   Tools/Screenshots/capture.sh [ipad]
set -euo pipefail
cd "$(dirname "$0")/../.."

OS="18.6"
BUNDLE=com.leonkazaryan.nomaded
if [ "${1:-}" = ipad ]; then
    DEVICE="iPad Pro 13-inch (M4)"
    OUT=Tools/Screenshots/output/ipad/raw
else
    DEVICE="iPhone 16 Pro Max"
    OUT=Tools/Screenshots/output/raw
fi
BUILD="${TMPDIR:-/tmp}/nomaded-screenshots"

# A traveler with 34 countries on six continents; Japan is left for the marking scene.
VISITED="IT,FR,ES,PT,DE,NL,CH,AT,CZ,GR,HR,GB,IE,NO,IS,TH,VN,ID,TR,AE,GE,KZ,KR,US,CA,MX,BR,AR,PE,MA,EG,ZA,AU,NZ"
# Exactly 25, so the top bar agrees with the 25-country medal.
VISITED_25="IT,FR,ES,PT,DE,NL,CH,AT,CZ,GR,HR,GB,IE,NO,TH,VN,TR,AE,GE,US,CA,MX,BR,MA,AU"

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
# 9:41, full battery and bars, like Apple's own screenshots.
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100 \
    || true # a Wi-Fi iPad has no cellular bars to set

launch() {
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${COMMON[@]}" "$@" >/dev/null
}

shot() { # name, seconds to wait, launch arguments…
    local name=$1 wait=$2
    shift 2
    launch "$@"
    sleep "$wait"
    xcrun simctl io "$UDID" screenshot "$DIR/$name.png" >/dev/null 2>&1
}

for LANGUAGE in en ru; do
    DIR="$OUT/$LANGUAGE"
    mkdir -p "$DIR"
    if [ "$LANGUAGE" = ru ]; then
        COMMON=(-NomadedDebugShowsFrameRate NO -AppleLanguages "(ru)" -AppleLocale ru_RU)
        CITIES="Париж:FR:48.86:2.35,Ницца:FR:43.70:7.27,Лион:FR:45.76:4.84,Бордо:FR:44.84:-0.58"
    else
        COMMON=(-NomadedDebugShowsFrameRate NO -AppleLanguages "(en)" -AppleLocale en_US)
        CITIES="Paris:FR:48.86:2.35,Nice:FR:43.70:7.27,Lyon:FR:45.76:4.84,Bordeaux:FR:44.84:-0.58"
    fi
    echo "Capturing ${LANGUAGE}…"
    # A first run warms the app up, so the timings below hold.
    launch -NomadedDebugVisited "$VISITED"
    sleep 6

    shot globe 7 -NomadedDebugVisited "$VISITED"
    shot cities 7 -NomadedDebugVisited "$VISITED" -NomadedDebugSelect FR -NomadedDebugCities "$CITIES"
    shot statistics 8 -NomadedDebugVisited "$VISITED" -NomadedDebugStats YES
    shot continent 9 -NomadedDebugVisited "$VISITED" -NomadedDebugStats YES -NomadedDebugContinent europe
    shot medal 7 -NomadedDebugVisited "$VISITED_25" -NomadedDebugMilestone countries.25

    # The celebration lasts about a second: a burst, and mark.png is the frame with the confetti.
    launch -NomadedDebugVisited "$VISITED" -NomadedDebugMark JP
    sleep 7.2
    for frame in 1 2 3 4; do
        xcrun simctl io "$UDID" screenshot "$DIR/mark-$frame.png" >/dev/null 2>&1
    done
    cp "$DIR/mark-2.png" "$DIR/mark.png"
done

xcrun simctl status_bar "$UDID" clear
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "Raw screenshots: $OUT. Check mark.png (or pick another mark-N), then run compose.swift."
