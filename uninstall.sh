#!/bin/zsh
set -e

# HermesViz Uninstall Script
# Removes HermesViz.app, hermes-agent backend, and config

echo "🧹 Uninstalling HermesViz..."

APP_NAME="HermesViz"
HERMES_DIR="$HOME/.hermes"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Kill running processes
if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    echo "  Stopping running instances..."
    pkill -f "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# 2. Remove .app bundles
for dir in "$PROJECT_DIR/$APP_NAME.app" "/Applications/$APP_NAME.app"; do
    if [ -d "$dir" ]; then
        echo "  Removing $dir..."
        rm -rf "$dir"
    fi
done

# 3. Remove hermes-agent backend (~100MB)
if [ -d "$HERMES_DIR/hermes-agent" ]; then
    echo "  Removing hermes-agent backend..."
    rm -rf "$HERMES_DIR/hermes-agent"
fi

# 4. Remove config
if [ -f "$HERMES_DIR/config.yaml" ]; then
    echo "  Removing config.yaml..."
    rm -f "$HERMES_DIR/config.yaml"
fi

# 5. Remove ~/.hermes if now empty
if [ -d "$HERMES_DIR" ] && [ -z "$(ls -A "$HERMES_DIR" 2>/dev/null)" ]; then
    echo "  Removing empty ~/.hermes..."
    rmdir "$HERMES_DIR" 2>/dev/null || true
fi

# 6. Clean build artifacts
if [ -d "$PROJECT_DIR/.build" ]; then
    echo "  Cleaning build artifacts..."
    rm -rf "$PROJECT_DIR/.build"
fi

echo ""
echo "✅ HermesViz uninstalled."
echo ""
echo "   To also remove the source code:"
echo "   rm -rf $PROJECT_DIR"
