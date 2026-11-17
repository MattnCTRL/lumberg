#!/bin/zsh
# Builds Lumberg.app. `scripts/build.sh --install` also copies it to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d Lumberg/Resources/Assets.xcassets ]] || scripts/make-icon.sh
xcodegen generate --quiet
xcodebuild -project Lumberg.xcodeproj -scheme Lumberg -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build
app=build/Build/Products/Release/Lumberg.app
echo "built $app"
if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "Lumberg"' 2>/dev/null || true
  rm -rf /Applications/Lumberg.app
  ditto "$app" /Applications/Lumberg.app
  open /Applications/Lumberg.app
  echo "installed to /Applications/Lumberg.app"
fi
