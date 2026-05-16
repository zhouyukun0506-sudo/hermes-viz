#!/bin/zsh

# HermesViz Build & Package Script
# Creates a portable .app bundle

APP_NAME="HermesViz"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/apple/Products/Release"
APP_BUNDLE="$APP_NAME.app"

echo "🚀 Building $APP_NAME for Release..."

# Clean previous build
rm -rf $APP_BUNDLE
rm -rf $BUILD_DIR

# Build the Swift executable
swift build -c release --arch arm64 --arch x86_64

# Create the .app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy resources (Bridge Script)
# Assuming the bridge script is a resource in the package
# We can find it in the build artifacts
find .build -name "hermes_chat_bridge.py" -exec cp {} "$APP_BUNDLE/Contents/Resources/" \;

# Create Info.plist if missing (basic version)
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

echo "✅ Done: $APP_BUNDLE"
echo "📦 You can now share this .app with others."
echo "Note: First-time users will be guided to install the Hermes backend automatically."
