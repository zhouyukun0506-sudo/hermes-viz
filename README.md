# HermesViz

A native macOS chat interface for the Hermes Agent, built with Swift.

## Quick Deploy

### Option A: Installer Package (recommended)

```bash
./make-installer.sh
# → HermesViz-Installer.dmg
```

Mount the DMG → double-click `HermesViz.pkg` → step-by-step install wizard.  
**Re-run to upgrade — overwrites existing install automatically.**

### Option B: Run from source

```bash
git clone https://github.com/zhouyukun0506-sudo/hermes-viz.git
cd hermes-viz
./run.sh
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

**No other prerequisites** — the in-app installer automatically provisions:
- Homebrew (if missing)
- Python 3.12+ (auto-installed via brew)
- git (auto-installed via brew)
- hermes-agent (cloned, venv created, dependencies installed)

## Features

- **Multi-turn Continuity**: Persistent bridge server keeps agent context alive across requests.
- **Zero-Dependency Setup**: One-click install automatically provisions Python, git, Homebrew, and hermes-agent — no terminal required.
- **Rich Visualization**: Thinking panels, tool execution cards, and real-time token tracking.
- **Interruptible**: Stop long-running tasks or generation at any time.
- **Built-in Settings**: Install, configure, and uninstall Hermes Agent directly from the Settings tab — no terminal needed. Uses official `hermes` CLI commands (`hermes setup`, `hermes config set`, `hermes doctor`, `hermes uninstall`).

## Project Structure

```
hermes-viz/
├── Sources/          # Swift source code
├── Package.swift     # Swift Package Manager manifest
├── make-installer.sh # Build .pkg installer + DMG
├── run.sh            # Build & launch in one command
├── build-app.sh      # Package into .app bundle
├── uninstall.sh      # One-click cleanup
├── Sources/Views/SettingsView.swift  # In-app Hermes CLI settings
└── requirements.txt  # Python bridge dependencies
```
