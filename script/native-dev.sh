#!/bin/bash
# "StripMuxX Native Dev": a debug build with its own bundle ID, command socket and app
# data, run in native mode in place of the installed StripMuxX, which it never replaces.
#
#   script/native-dev.sh run      build, sign, quit the installed app, launch the dev app
#   script/native-dev.sh stop     quit the dev app and relaunch the installed one
#   script/native-dev.sh cli ...  run a command against the dev app
#
# Accessibility must be granted once to "StripMuxX Native Dev"; builds are signed with the
# same local identity, so the grant survives rebuilds. The two apps never run together,
# so the dev app shares the installed app's data folder, as its native mode would.
set -euo pipefail
cd "$(dirname "$0")/.."

app=".debug/StripMuxX Native Dev.app"
installed=/Applications/StripMuxX.app
config="${WINMUX_NATIVE_CONFIG:-$HOME/.config/stripmuxx/native-spaces-test-144.toml}"
identity=""
for dir in stripmuxx winmux-gf; do
    if [ -f "$HOME/.config/$dir/signing-identity" ]; then identity="$(cat "$HOME/.config/$dir/signing-identity")"; break; fi
done

stop_dev() { pkill -f "$app/Contents/MacOS/WinMuxApp" 2>/dev/null || true; }

case "${1:-run}" in
    run)
        test -f "$config" || { echo "Missing native config: $config" >&2; exit 1; }
        (source ./script/setup.sh >/dev/null && swift build --product WinMuxApp && swift build --product stripmuxx)
        rm -rf "$app"
        mkdir -p "$app/Contents/MacOS"
        cp .build/debug/WinMuxApp "$app/Contents/MacOS/WinMuxApp"
        # The debug binary looks for frameworks and SwiftPM resources next to itself.
        ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
            "$app/Contents/MacOS/Sparkle.framework"
        for bundle in .build/debug/*.bundle; do ditto "$bundle" "$app/Contents/MacOS/$(basename "$bundle")"; done
        /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.gfavaro.stripmuxx.debug" \
            -c "Add :CFBundleName string StripMuxX Native Dev" \
            -c "Add :CFBundleExecutable string WinMuxApp" \
            -c "Add :CFBundlePackageType string APPL" \
            -c "Add :LSUIElement bool true" "$app/Contents/Info.plist" >/dev/null
        codesign --force --deep --sign "$identity" --identifier com.gfavaro.stripmuxx.debug "$app" >/dev/null 2>&1
        stop_dev
        pkill -f "$installed/Contents/MacOS/StripMuxX" 2>/dev/null || true
        sleep 1
        open "$app" --args --config-path "$config"
        echo "StripMuxX Native Dev running with $config; installed StripMuxX is stopped."
        ;;
    stop)
        stop_dev
        sleep 1
        open "$installed"
        echo "StripMuxX Native Dev stopped; installed StripMuxX relaunched."
        ;;
    cli)
        shift
        exec .build/debug/stripmuxx "$@"
        ;;
    *)
        echo "usage: $0 run|stop|cli <command>" >&2
        exit 2
        ;;
esac
