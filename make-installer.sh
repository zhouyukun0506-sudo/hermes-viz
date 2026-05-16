#!/bin/zsh
set -e

APP_NAME="HermesViz"
PKG_NAME="${APP_NAME}.pkg"
DMG_NAME="${APP_NAME}-Installer.dmg"
STAGING="$(mktemp -d /tmp/hermesviz-pkg.XXXXXX)"

echo "📦 Building ${APP_NAME} installer..."

# 1. Build .app
echo "  Building .app..."
swift build -c release 2>&1 | tail -3
./build-app.sh 2>&1

# 2. Bundle offline resources (hermes-agent + wheels)
if [ -f bundle-offline.sh ] && [ -d "/Users/ethan_chou/.hermes/hermes-agent" ]; then
    echo "  Bundling offline resources..."
    ./bundle-offline.sh 2>&1 | grep "→"
else
    echo "  ⚠️  Offline bundle skipped (no hermes-agent source available)."
    echo "     The installer will download hermes-agent on first run."
fi

# 2. Create standalone installer package
echo "  Creating installer package..."
pkgbuild \
    --component "${APP_NAME}.app" \
    --install-location /Applications \
    --identifier "com.hermes.viz" \
    --version "1.0.0" \
    --ownership preserve \
    --scripts /dev/null \
    "${STAGING}/${PKG_NAME}" 2>&1

echo "  → $(du -sh "${STAGING}/${PKG_NAME}" | cut -f1)"

# 3. Wrap in DMG
echo "  Creating DMG..."
rm -f "${DMG_NAME}"
hdiutil create -volname "${APP_NAME} Installer" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_NAME}" 2>&1 | tail -1

echo ""
echo "✅ ${DMG_NAME} ($(du -sh "${DMG_NAME}" | cut -f1))"
echo "   Mount DMG → Double-click HermesViz.pkg → Install wizard."
echo "   Re-run installer to upgrade — no manual delete needed."

rm -rf "${STAGING}"
