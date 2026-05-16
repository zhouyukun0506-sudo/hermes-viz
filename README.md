# HermesViz – macOS Native Agent Dashboard

SwiftUI native app for visualizing Hermes Agent data.

## Build

```bash
cd hermes-viz
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

## Architecture

```
Sources/
├── HermesVizApp.swift          @main entry + NavigationSplitView
├── Models/DataModels.swift     Codable structs
├── Services/HermesDataService.swift   @Observable singleton data layer
└── Views/
    ├── DashboardView.swift     概览: stat cards + daily token bar chart
    ├── SessionsView.swift      会话: searchable Table + platform filter
    ├── AnalyticsView.swift     分析: Swift Charts line/area + donut
    ├── SkillsView.swift        技能: installed agent skills list
    └── CronView.swift          任务: scheduled cron job monitor
```

## Data Sources

Reads directly from `~/.hermes/`:
- `sessions/sessions.json` – session index
- `sessions/session_*.json` – individual session details (model, messages)
- `gateway_state.json` – agent running status
- `skills/*/SKILL.md` – installed agent skills
- `cron/` + `crontab.json` – scheduled tasks

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ with Swift 5.9 toolchain
- No third-party binaries bundled (pure SwiftUI + Yams for YAML)
