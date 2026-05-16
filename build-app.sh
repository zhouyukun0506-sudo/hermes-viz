#!/bin/zsh

# HermesViz Build & Package Script
# Creates a portable .app bundle

APP_NAME="HermesViz"
APP_BUNDLE="$APP_NAME.app"

echo "🚀 Building $APP_NAME for Release..."

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Build the Swift executable
swift build -c release

# Create the .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Find and copy the executable
BINARY_PATH=$(find .build -name "$APP_NAME" -type f -not -path "*/DWARF/*" | head -n 1)
if [ -f "$BINARY_PATH" ]; then
    cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/"
    echo "✅ Copied binary from $BINARY_PATH"
else
    echo "❌ Error: Could not find binary!"
    exit 1
fi

# Copy resources (Bridge Script & Icon)
find .build -name "hermes_chat_bridge.py" -exec cp {} "$APP_BUNDLE/Contents/Resources/" \;
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi
echo "✅ Copied resources and icon"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.hermes.viz</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✨ Done: $APP_BUNDLE"
echo "📦 This bundle is now ready to be distributed."
