#!/bin/zsh
set -e

APP_NAME="HermesViz"
DMG_NAME="${APP_NAME}.dmg"
VOL_NAME="${APP_NAME} Installer"
STAGING_DIR="$(mktemp -d /tmp/hermesviz-dmg.XXXXXX)"

echo "📦 Building DMG for ${APP_NAME}..."

# 1. Ensure .app is built
if [ ! -d "${APP_NAME}.app" ]; then
    echo "  Building .app first..."
    swift build -c release 2>&1 | tail -3
    ./build-app.sh 2>&1
fi

# 2. Prepare staging
echo "  Preparing DMG layout..."
cp -R "${APP_NAME}.app" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

# 3. Remove old DMG
rm -f "${DMG_NAME}"

# 4. Create DMG
echo "  Creating ${DMG_NAME}..."
hdiutil create -volname "${VOL_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_NAME}" 2>&1 | tail -1

# 5. Cleanup
rm -rf "${STAGING_DIR}"

echo ""
echo "✅ ${DMG_NAME} created ($(du -sh "${DMG_NAME}" | cut -f1))"
echo "   Distribute this file — user drags HermesViz.app to /Applications to install/upgrade."
