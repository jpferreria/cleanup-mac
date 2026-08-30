#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: ./create_icon.sh <path_to_jpg>"
    exit 1
fi

INPUT_IMG="$1"
echo "Converting image to PNG..."
sips -s format png "$INPUT_IMG" --out AppIcon.png

echo "Creating iconset directory..."
mkdir -p AppIcon.iconset

echo "Generating icons of different sizes..."
sips -z 16 16     AppIcon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     AppIcon.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   AppIcon.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   AppIcon.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   AppIcon.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 AppIcon.png --out AppIcon.iconset/icon_512x512@2x.png

echo "Bundling into AppIcon.icns..."
iconutil -c icns AppIcon.iconset -o AppIcon.icns

echo "Cleaning up temporary files..."
rm -rf AppIcon.png AppIcon.iconset

echo "Icon generated successfully!"
