#!/bin/zsh
# Regenerates the app icon from the ASCII portrait.
set -euo pipefail
cd "$(dirname "$0")/.."
set_dir=Lumberg/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p "$set_dir"
tmp=$(mktemp -d)
swift run --package-path Core lumberg-ascii icon "$tmp/icon.png"
for s in 16 32 64 128 256 512 1024; do
  sips -z $s $s "$tmp/icon.png" --out "$set_dir/icon_$s.png" >/dev/null
done
rm -rf "$tmp"
cat > Lumberg/Resources/Assets.xcassets/Contents.json <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
cat > "$set_dir/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_64.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_1024.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
echo "icon written to $set_dir"
