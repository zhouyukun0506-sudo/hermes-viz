# HermesViz

A native macOS chat interface for the Hermes Agent, built with Swift.

## Quick Deploy

```bash
# 1. Clone
git clone https://github.com/zhouyukun0506-sudo/hermes-viz.git
cd hermes-viz

# 2. Build & Launch
./run.sh
```

Or package into a standalone `.app` bundle:

```bash
./build-app.sh
# → HermesViz.app ready to use or share
```

## Uninstall

```bash
# One command removes everything (app, backend, config, build artifacts)
./uninstall.sh
```

What it cleans up:
- `HermesViz.app` (project dir + `/Applications`)
- `~/.hermes/hermes-agent` backend (~100MB)
- `~/.hermes/config.yaml`
- `.build/` artifacts

To also delete the source code after uninstall:

```bash
cd .. && rm -rf hermes-viz
```

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Swift 5.9+
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) installed at `~/.hermes/`

## Features

- **Multi-turn Continuity**: Persistent bridge server keeps agent context alive across requests.
- **Onboarding**: Auto-detects if the backend is installed and provides one-click setup.
- **Rich Visualization**: Thinking panels, tool execution cards, and real-time token tracking.
- **Interruptible**: Stop long-running tasks or generation at any time.

## Project Structure

```
hermes-viz/
├── Sources/          # Swift source code
├── Package.swift     # Swift Package Manager manifest
├── run.sh            # Build & launch in one command
├── build-app.sh      # Package into .app bundle
├── uninstall.sh      # One-click cleanup
└── requirements.txt  # Python bridge dependencies
```
