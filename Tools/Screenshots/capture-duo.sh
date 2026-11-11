#!/bin/bash
# App Store screenshots for iPhone Duo: the app's own scenes on the iPhone Duo simulator
# (iOS 27.2 build 24B91016s), folded on the outer display (1398×2034) and open like a book on the
# inner one (2853×2007). Only Device Hub can fold and open the Duo, so the script shoots the
# folded scenes, then waits for the Duo to be opened. Raw shots go to output/duo/raw/<language>/,
# compose.swift then lays them out. See README.md.
#
#   Tools/Screenshots/capture-duo.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

BUNDLE=com.leonkazaryan.nomaded
DEVICE_HUB=/Applications/Xcode.app/Contents/Applications/DeviceHub.app
OUT=Tools/Screenshots/output/duo/raw
BUILD="${TMPDIR:-/tmp}/nomaded-screenshots-duo"
PROBE="$BUILD/probe.png"

# The same traveler as on the iPhone: 34 countries on six continents.
VISITED="IT,FR,ES,PT,DE,NL,CH,AT,CZ,GR,HR,GB,IE,NO,IS,TH,VN,ID,TR,AE,GE,KZ,KR,US,CA,MX,BR,AR,PE,MA,EG,ZA,AU,NZ"
# Exactly 25, so the counter agrees with the 25-country medal.
VISITED_25="IT,FR,ES,PT,DE,NL,CH,AT,CZ,GR,HR,GB,IE,NO,TH,VN,TR,AE,GE,US,CA,MX,BR,MA,AU"

UDID=$(xcrun simctl list devices available | awk '/^    iPhone Duo \(/ { match($0, /\([0-9A-F-]+\)/); print substr($0, RSTART + 1, RLENGTH - 2); exit }')
[ -n "$UDID" ] || { echo "No iPhone Duo simulator. It needs the iOS 27.2 runtime build 24B91016s (CLAUDE.md)."; exit 1; }
# The Duo draws its displays only while Device Hub is open.
pgrep -x DeviceHub >/dev/null || open -a "$DEVICE_HUB"
xcrun simctl list devices | grep "$UDID" | grep -q Booted \
    || { echo "Boot the iPhone Duo in Device Hub, wait for its home screen, then run this again."; exit 1; }

echo "Building for iPhone Duo…"
mkdir -p "$BUILD"
xcodebuild -project Nomaded.xcodeproj -scheme Nomaded -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$BUILD" -quiet build 2>&1 | grep -v appintentsmetadataprocessor || true
xcrun simctl install "$UDID" "$BUILD/Build/Products/Debug-iphonesimulator/Nomaded.app"
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" --batteryState charged --batteryLevel 100

# A display that's off shoots plain black, about 100 KB of PNG; one in use, megabytes.
is_on() { # display
    xcrun simctl io "$UDID" screenshot --display="$1" "$PROBE" >/dev/null 2>&1 && [ "$(stat -f %z "$PROBE")" -gt 500000 ]
}

wait_for() { # display, what to ask for
    is_on "$1" && return
    echo "$2"
    until is_on "$1"; do sleep 2; done
    sleep 3
}

launch() {
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${COMMON[@]}" "$@" >/dev/null
}

shot() { # display, name, seconds to wait, launch arguments…
    local display=$1 name=$2 wait=$3
    shift 3
    launch "$@"
    sleep "$wait"
    xcrun simctl io "$UDID" screenshot --display="$display" "$DIR/$name.png" >/dev/null 2>&1
}

use_language() {
    DIR="$OUT/$1"
    mkdir -p "$DIR"
    if [ "$1" = ru ]; then
        COMMON=(-NomadedDebugShowsFrameRate NO -AppleLanguages "(ru)" -AppleLocale ru_RU)
        CITIES="Париж:FR:48.86:2.35,Ницца:FR:43.70:7.27,Лион:FR:45.76:4.84,Бордо:FR:44.84:-0.58"
    else
        COMMON=(-NomadedDebugShowsFrameRate NO -AppleLanguages "(en)" -AppleLocale en_US)
        CITIES="Paris:FR:48.86:2.35,Nice:FR:43.70:7.27,Lyon:FR:45.76:4.84,Bordeaux:FR:44.84:-0.58"
    fi
}

capture_folded() {
    for LANGUAGE in en ru; do
        use_language "$LANGUAGE"
        echo "Capturing ${LANGUAGE}, folded…"
        # A first run warms the app up, so the timings below hold.
        launch -NomadedDebugVisited "$VISITED"
        sleep 8
        shot 1 cover-globe 8 -NomadedDebugVisited "$VISITED"
        shot 1 cover-card 9 -NomadedDebugVisited "$VISITED" -NomadedDebugSelect FR -NomadedDebugCities "$CITIES"
        shot 1 cover-statistics 13 -NomadedDebugVisited "$VISITED" -NomadedDebugStats YES
    done
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
}

capture_open() {
    for LANGUAGE in en ru; do
        use_language "$LANGUAGE"
        echo "Capturing ${LANGUAGE}, open…"
        launch -NomadedDebugVisited "$VISITED"
        sleep 8
        shot 3 globe 8 -NomadedDebugVisited "$VISITED"
        shot 3 card 9 -NomadedDebugVisited "$VISITED" -NomadedDebugSelect FR -NomadedDebugCities "$CITIES"
        shot 3 statistics 13 -NomadedDebugVisited "$VISITED" -NomadedDebugStats YES
        shot 3 medal 15 -NomadedDebugVisited "$VISITED_25" -NomadedDebugMilestone countries.25
        shot 3 story 14 -NomadedDebugVisited "$VISITED" -NomadedDebugShare YES
    done
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
}

# Whichever posture the Duo is in first, so it changes posture once.
OPEN_HINT="Open the iPhone Duo in Device Hub, flat, held like a book: these scenes are shot on the inner display."
FOLDED_HINT="Fold the iPhone Duo in Device Hub: these scenes are shot on the outer display."
if is_on 3; then
    capture_open
    wait_for 1 "$FOLDED_HINT"
    capture_folded
else
    wait_for 1 "$FOLDED_HINT"
    capture_folded
    wait_for 3 "$OPEN_HINT"
    capture_open
fi

xcrun simctl status_bar "$UDID" clear
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "Raw screenshots: $OUT. Now run: swift Tools/Screenshots/compose.swift Tools/Screenshots/output/duo duo"
