import SwiftUI

// MARK: - Installation Status

struct HermesStatus {
    var cliInstalled = false
    var cliPath = ""
    var agentInstalled = false
    var agentPath: String { NSHomeDirectory() + "/.hermes/hermes-agent" }
    var configExists = false
    var configPath: String { NSHomeDirectory() + "/.hermes/config.yaml" }
    var checked = false
}

// MARK: - CLI Runner

@Observable
final class HermesCLI {
    private(set) var output = ""
    private(set) var isRunning = false
    private(set) var lastError: String?

    func checkInstallation() -> HermesStatus {
        var status = HermesStatus()
        let home = NSHomeDirectory()

        let localCLI = home + "/.local/bin/hermes"
        status.cliInstalled = FileManager.default.fileExists(atPath: localCLI)
        status.cliPath = status.cliInstalled ? localCLI : "(not found)"

        let agentDir = home + "/.hermes/hermes-agent"
        let venvPython = agentDir + "/venv/bin/python3"
        status.agentInstalled = FileManager.default.fileExists(atPath: venvPython)

        let configFile = home + "/.hermes/config.yaml"
        status.configExists = FileManager.default.fileExists(atPath: configFile)

        status.checked = true
        return status
    }

    func resolveHermesPath() -> String? {
        let local = NSHomeDirectory() + "/.local/bin/hermes"
        if FileManager.default.fileExists(atPath: local) { return local }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["hermes"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                return path
            }
        } catch {}
        return nil
    }

    func readConfig() -> String {
        let path = NSHomeDirectory() + "/.hermes/config.yaml"
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "(no config found)"
        }
        return data.replacingOccurrences(
            of: #"api_key:\s*\S+"#,
            with: "api_key: ***",
            options: .regularExpression
        )
    }

    func run(_ args: [String], onComplete: ((Bool) -> Void)? = nil) {
        guard let hermesPath = resolveHermesPath() else {
            output += "\n⚠️ hermes CLI not found. Install it first.\n"
            lastError = "hermes not found"
            onComplete?(false)
            return
        }

        isRunning = true
        lastError = nil
        output += "\n$ hermes \(args.joined(separator: " "))\n"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: hermesPath)
            process.arguments = args
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = NSHomeDirectory()
            env["USER"] = NSUserName()
            env["HERMES_HOME"] = NSHomeDirectory() + "/.hermes"
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
                let outStr = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let combined = outStr + (errStr.isEmpty ? "" : "\n\(errStr)")
                let success = process.terminationStatus == 0

                DispatchQueue.main.async {
                    self.output += combined
                    if !combined.hasSuffix("\n") { self.output += "\n" }
                    self.isRunning = false
                    if !success {
                        self.lastError = errStr.isEmpty
                            ? "Exit code \(process.terminationStatus)"
                            : errStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    onComplete?(success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.output += "Process error: \(error.localizedDescription)\n"
                    self.isRunning = false
                    self.lastError = error.localizedDescription
                    onComplete?(false)
                }
            }
        }
    }

    func clearOutput() {
        output = ""
        lastError = nil
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @State private var cli = HermesCLI()
    @State private var status = HermesStatus()
    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    @State private var configPreview: String = "(loading...)"
    @State private var showUninstallConfirm = false
    @State private var showFullUninstallConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                statusSection
                Divider()
                installSection
                Divider()
                configSection
                Divider()
                toolsSection
                Divider()
                dangerSection
                Divider()
                outputSection
            }
            .padding(24)
        }
        .background(Color.wxBase)
        .onAppear { refreshAll() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill").font(.title2).foregroundStyle(Color.wxAccent)
            Text("Settings").font(.title2.bold())
            Spacer()
            Button { refreshAll() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh").font(.caption)
                }
            }
            .disabled(cli.isRunning)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installation Status", systemImage: "info.circle").font(.headline)
            if !status.checked {
                ProgressView("Checking...")
            } else {
                StatusRow(label: "hermes CLI", ok: status.cliInstalled,
                    detail: status.cliInstalled ? status.cliPath : "Not installed — run setup below")
                StatusRow(label: "Hermes Agent", ok: status.agentInstalled,
                    detail: status.agentInstalled ? status.agentPath : "Not installed")
                StatusRow(label: "Config (config.yaml)", ok: status.configExists,
                    detail: status.configExists ? status.configPath : "Not created — configure below")
            }
        }
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(status.cliInstalled ? "Reconfigure" : "Install Hermes",
                  systemImage: "arrow.down.to.line").font(.headline)
            if !status.cliInstalled {
                Text("Hermes CLI is not installed. One-click setup downloads and configures everything.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    cli.clearOutput()
                    cli.run(["setup", "--non-interactive"]) { _ in refreshAll() }
                } label: {
                    Label("One-Click Install: hermes setup", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(cli.isRunning)
            } else {
                Text("Hermes is installed.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        cli.clearOutput()
                        cli.run(["setup", "--quick"]) { _ in refreshAll() }
                    } label: { Label("Quick Setup", systemImage: "lightning.fill") }
                        .disabled(cli.isRunning)
                    Button {
                        cli.clearOutput()
                        cli.run(["setup", "--reconfigure"]) { _ in refreshAll() }
                    } label: { Label("Full Reconfigure", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(cli.isRunning)
                }
            }
            if cli.isRunning { ProgressView().controlSize(.small) }
        }
    }

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model & API Key", systemImage: "key.fill").font(.headline)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model").font(.caption2).foregroundStyle(.tertiary)
                    TextField("e.g. gpt-4o", text: $modelName)
                        .textFieldStyle(.roundedBorder).frame(minWidth: 130)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key").font(.caption2).foregroundStyle(.tertiary)
                    SecureField("sk-...", text: $apiKey).textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 8) {
                Button {
                    let m = modelName.trimmingCharacters(in: .whitespaces)
                    guard !m.isEmpty else { return }
                    cli.clearOutput()
                    cli.run(["config", "set", "model", m]) { _ in refreshAll() }
                } label: { Label("Set Model", systemImage: "checkmark") }
                    .disabled(modelName.trimmingCharacters(in: .whitespaces).isEmpty || cli.isRunning)
                Button {
                    let k = apiKey.trimmingCharacters(in: .whitespaces)
                    guard !k.isEmpty else { return }
                    cli.clearOutput()
                    cli.run(["config", "set", "api_key", k]) { _ in refreshAll() }
                } label: { Label("Set API Key", systemImage: "checkmark") }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || cli.isRunning)
                Button {
                    cli.clearOutput()
                    cli.run(["model"]) { _ in refreshAll() }
                } label: { Label("Interactive Picker", systemImage: "rectangle.and.pencil.and.ellipsis") }
                    .disabled(cli.isRunning)
            }
            ScrollView {
                Text(configPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            Button {
                cli.clearOutput()
                cli.run(["config", "show"]) { _ in configPreview = cli.readConfig() }
            } label: {
                Label("hermes config show", systemImage: "arrow.clockwise").font(.caption)
            }
            .disabled(cli.isRunning)
            if cli.isRunning { ProgressView().controlSize(.small) }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Diagnostics", systemImage: "stethoscope").font(.headline)
            HStack(spacing: 12) {
                Button {
                    cli.clearOutput()
                    cli.run(["doctor"]) { _ in refreshAll() }
                } label: { Label("hermes doctor", systemImage: "play.fill") }
                    .disabled(cli.isRunning)
                Button {
                    cli.clearOutput()
                    cli.run(["status"]) { _ in refreshAll() }
                } label: { Label("hermes status", systemImage: "antenna.radiowaves.left.and.right") }
                    .disabled(cli.isRunning)
            }
            if cli.isRunning { ProgressView().controlSize(.small) }
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Uninstall", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).font(.headline)
            if !showUninstallConfirm {
                Button(role: .destructive) {
                    showUninstallConfirm = true
                } label: { Label("Uninstall Hermes...", systemImage: "trash") }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose uninstall scope:").font(.caption).foregroundStyle(.secondary)
                    if !showFullUninstallConfirm {
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                cli.clearOutput()
                                cli.run(["uninstall", "--yes"]) { _ in
                                    refreshAll(); showUninstallConfirm = false
                                }
                            } label: { Label("Keep configs", systemImage: "trash") }.disabled(cli.isRunning)
                            Button(role: .destructive) {
                                showFullUninstallConfirm = true
                            } label: { Label("Remove everything...", systemImage: "trash.fill") }.disabled(cli.isRunning)
                            Button("Cancel") { showUninstallConfirm = false }
                        }
                    } else {
                        Text("⚠️ This removes ALL files including configs and session data.")
                            .font(.caption).foregroundStyle(.red)
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                cli.clearOutput()
                                cli.run(["uninstall", "--yes", "--full"]) { _ in
                                    refreshAll(); showUninstallConfirm = false; showFullUninstallConfirm = false
                                }
                            } label: { Label("Confirm Full Uninstall", systemImage: "trash.fill") }.disabled(cli.isRunning)
                            Button("Cancel") { showUninstallConfirm = false; showFullUninstallConfirm = false }
                        }
                    }
                }
            }
            if cli.isRunning { ProgressView().controlSize(.small) }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Command Output", systemImage: "terminal").font(.headline)
            if !cli.output.isEmpty {
                ScrollView {
                    Text(cli.output)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 80, maxHeight: 180)
                Button { cli.clearOutput() } label: {
                    Label("Clear", systemImage: "xmark.circle").font(.caption)
                }
            } else {
                Text("Command output will appear here.").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func refreshAll() {
        status = cli.checkInstallation()
        configPreview = cli.readConfig()
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let label: String
    let ok: Bool
    let detail: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color.green : Color.red.opacity(0.6)).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.primary)
            Spacer()
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
    }
}
