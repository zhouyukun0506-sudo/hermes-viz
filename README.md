# Hermes Modern Chat Interface

A professional, high-fidelity macOS chat interface for the [Hermes Agent](https://github.com/NousResearch/hermes-agent).

## Features

- **Multi-turn Continuity**: Persistent bridge server keeps agent context alive across requests.
- **Portability**: Auto-onboarding guides users through backend installation and configuration.
- **Rich Visualization**: Thinking panels, tool execution cards, and real-time token tracking.
- **Interruptible**: Stop long-running tasks or generation at any time with the Stop button.

## Distribution

The project includes a `build-app.sh` script to package the application as a standalone `.app` bundle.

### Prerequisites for Distribution

- macOS 13.0+
- Swift 5.9+
- Git

### Build Instructions

```bash
./build-app.sh
```

The resulting `HermesViz.app` can be moved to the `/Applications` folder or shared with others.

## Onboarding Flow

When a user launches the app for the first time:
1. It detects if the `hermes-agent` backend is installed in `~/.hermes/`.
2. If missing, it provides a one-click setup to clone and install the backend.
3. It provides a graphical configuration wizard for API keys and model selection.

## GitHub

This project is ready to be pushed to GitHub:

```bash
git remote add origin <your-repo-url>
git push -u origin main
```
