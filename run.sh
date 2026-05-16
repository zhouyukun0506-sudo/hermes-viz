#!/bin/bash
set -e
cd "$(dirname "$0")"
echo "Building..."
swift build -c release 2>&1 | tail -3
echo "Launching HermesViz..."
open .build/release/HermesViz
echo "Done. You can close this terminal."
