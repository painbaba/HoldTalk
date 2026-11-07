#!/bin/bash
# Builds HoldTalk.app. Pass --install to copy it to ~/Applications.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift build -c release

app="build/HoldTalk.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/HoldTalk" "$app/Contents/MacOS/HoldTalk"
cp Resources/Info.plist "$app/Contents/Info.plist"

# macOS ties permission grants to the signature. A real certificate keeps them
# across rebuilds. An ad-hoc signature means granting them again after every build.
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development[^"]*\)".*/\1/p' | head -1)}"
if [ -n "$identity" ]; then
    codesign --force --sign "$identity" "$app"
    echo "Signed with: $identity"
else
    codesign --force --sign - "$app"
    echo "Signed ad-hoc: you'll need to grant permissions again after each rebuild."
fi

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    pkill -x HoldTalk 2>/dev/null || true
    rm -rf "$HOME/Applications/HoldTalk.app"
    cp -R "$app" "$HOME/Applications/HoldTalk.app"
    echo "Installed: $HOME/Applications/HoldTalk.app"
else
    echo "Built: $root/$app"
fi
