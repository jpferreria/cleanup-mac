#!/bin/bash
set -e

echo "Compiling CleanupApp.swift..."
SDK_PATH=$(xcrun --show-sdk-path)
swiftc -O -sdk "$SDK_PATH" -parse-as-library CleanupApp.swift -o Cleanup-Binary

echo "Creating App Bundle structure..."
mkdir -p Cleanup.app/Contents/MacOS
mkdir -p Cleanup.app/Contents/Resources

echo "Moving binary..."
mv Cleanup-Binary Cleanup.app/Contents/MacOS/Cleanup

if [ -f AppIcon.icns ]; then
    echo "Copying AppIcon.icns..."
    cp AppIcon.icns Cleanup.app/Contents/Resources/
fi

echo "Creating Info.plist..."
cat <<EOF > Cleanup.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Cleanup</string>
    <key>CFBundleIdentifier</key>
    <string>com.cleanup.mac</string>
    <key>CFBundleName</key>
    <string>Cleanup</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "Cleanup.app created successfully!"
