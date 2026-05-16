import SwiftUI
import Yams

/// ViewModel for running hermes CLI commands and reporting results.
@Observable
final class HermesCLI {
    private(set) var output = ""
    private(set) var isRunning = false
    private(set) var lastError: String?

    var hermesPath: String {
        let local = NSHomeDirectory() + "/.local/bin/hermes"
        if FileManager.default.fileExists(atPath: local) { return local }
        return "/usr/bin/env hermes"
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: hermesPath)
            || FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.hermes/hermes-agent/venv/bin/python3")
    }

    var configPath: String {
        NSHomeDirectory() + "/.hermes/config.yaml"
    }

    var hasConfig: Bool {
        FileManager.default.fileExists(atPath: configPath)
    }

    func readConfig() -> String {
        guard let data = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return "(no config found)"
        }
        let masked = data.replacingOccurrences(
            of: #"api_key:\s*\S+"#,
            with: "api_key: ***",
            options: .regularExpression
        )
        return masked
    }

    func run(_ args: [String], onComplete: ((Bool) -> Void)? = nil) {
        isRunning = true
        lastError = nil
        output += "\n$ hermes \(args.joined(separator: " "))\n"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.hermesPath)
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

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""

                let combined = outStr + (errStr.isEmpty ? "" : "\n[stderr]\n\(errStr)")
                let success = process.terminationStatus == 0

                DispatchQueue.main.async {
                    self.output += combined + "\n"
                    self.isRunning = false
                    if !success {
                        self.lastError = errStr.isEmpty ? "Exit code \(process.terminationStatus)" : errStr
                    }
                    onComplete?(success)
                }
            } catch {
                DispatchQueue.main.async {
                    self.output += "Error: \(error.localizedDescription)\n"
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
    @State private var apiKey: String = ""
    @State private var modelName: String = ""
    @State private var configPreview: String = ""
    @State private var showUninstallConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusSection
                installSection
                modelSection
                configPreviewSection
                doctorSection
                dangerSection
                outputSection
            }
            .padding(24)
        }
        .background(Color.wxBase)
        .onAppear { refreshStatus() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(Color.wxAccent)
            Text("Hermes Settings")
                .font(.title2.bold())
            Spacer()
            Button { refreshStatus() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(cli.isRunning)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        GroupBox(label: Label("Status", systemImage: "info.circle")) {
            VStack(alignment: .leading, spacing: 8) {
                statusRow(label: "Hermes CLI", ok: cli.isInstalled,
                          detail: cli.isInstalled ? cli.hermesPath : "Not found")
                statusRow(label: "Config File", ok: cli.hasConfig,
                          detail: cli.hasConfig ? cli.configPath : "Not created")
                statusRow(label: "Hermes Agent",
                          ok: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.hermes/hermes-agent"),
                          detail: "~/.hermes/hermes-agent")
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Install / Setup

    private var installSection: some View {
        GroupBox(label: Label(cli.isInstalled ? "Reconfigure" : "Install Hermes",
                              systemImage: "arrow.down.to.line")) {
            VStack(alignment: .leading, spacing: 10) {
                if !cli.isInstalled {
                    Text("Hermes Agent is not yet installed. Click below to run the official setup.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        cli.clearOutput()
                        cli.run(["setup", "--non-interactive"]) { _ in refreshStatus() }
                    } label: {
                        Label("Run: hermes setup --non-interactive", systemImage: "play.fill")
                    }
                    .disabled(cli.isRunning)
                } else {
                    Text("Hermes is installed. Re-run setup to change configuration.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button {
                            cli.clearOutput()
                            cli.run(["setup", "--reconfigure"]) { _ in refreshStatus() }
                        } label: {
                            Label("hermes setup --reconfigure", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(cli.isRunning)
                        Button {
                            cli.clearOutput()
                            cli.run(["setup", "--quick"]) { _ in refreshStatus() }
                        } label: {
                            Label("hermes setup --quick", systemImage: "lightning.fill")
                        }
                        .disabled(cli.isRunning)
                    }
                }
                if cli.isRunning { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Model & API Key

    private var modelSection: some View {
        GroupBox(label: Label("Model & API Key", systemImage: "key.fill")) {
            VStack(alignment: .leading, spacing: 12) {
                Text("hermes config set").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model").font(.caption2).foregroundStyle(.tertiary)
                        TextField("e.g. gpt-4o", text: $modelName)
                            .textFieldStyle(.roundedBorder).frame(minWidth: 120)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key").font(.caption2).foregroundStyle(.tertiary)
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        cli.clearOutput()
                        cli.run(["config", "set", "model", modelName.trimmingCharacters(in: .whitespaces)]) { s in
                            if s { refreshStatus() }
                        }
                    } label: { Label("Set Model", systemImage: "checkmark") }
                        .disabled(modelName.trimmingCharacters(in: .whitespaces).isEmpty || cli.isRunning)
                    Button {
                        cli.clearOutput()
                        cli.run(["config", "set", "api_key", apiKey.trimmingCharacters(in: .whitespaces)]) { s in
                            if s { refreshStatus() }
                        }
                    } label: { Label("Set API Key", systemImage: "checkmark") }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || cli.isRunning)
                }
                Button {
                    cli.clearOutput()
                    cli.run(["model"]) { _ in refreshStatus() }
                } label: {
                    Label("Interactive Model Picker: hermes model", systemImage: "rectangle.and.pencil.and.ellipsis")
                }
                .disabled(cli.isRunning)
                if cli.isRunning { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Config Preview

    private var configPreviewSection: some View {
        GroupBox(label: Label("Current Config", systemImage: "doc.text")) {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView {
                    Text(configPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                Button {
                    cli.clearOutput()
                    cli.run(["config", "show"]) { _ in configPreview = cli.readConfig() }
                } label: {
                    Label("Refresh: hermes config show", systemImage: "arrow.clockwise")
                }
                .disabled(cli.isRunning)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Doctor

    private var doctorSection: some View {
        GroupBox(label: Label("System Check", systemImage: "stethoscope")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run diagnostics to check configuration and dependencies.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button {
                        cli.clearOutput()
                        cli.run(["doctor"]) { _ in }
                    } label: { Label("hermes doctor", systemImage: "play.fill") }
                        .disabled(cli.isRunning)
                    Button {
                        cli.clearOutput()
                        cli.run(["status"]) { _ in }
                    } label: { Label("hermes status", systemImage: "antenna.radiowaves.left.and.right") }
                        .disabled(cli.isRunning)
                }
                if cli.isRunning { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Danger Zone

    private var dangerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.headline)
                if showUninstallConfirm {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This will remove Hermes Agent. Config files are kept by default unless you choose full uninstall.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                cli.clearOutput()
                                cli.run(["uninstall", "--yes"]) { _ in refreshStatus() }
                                showUninstallConfirm = false
                            } label: {
                                Label("hermes uninstall --yes", systemImage: "trash")
                            }
                            .disabled(cli.isRunning)
                            Button(role: .destructive) {
                                cli.clearOutput()
                                cli.run(["uninstall", "--yes", "--full"]) { _ in refreshStatus() }
                                showUninstallConfirm = false
                            } label: {
                                Label("hermes uninstall --full --yes", systemImage: "trash.fill")
                            }
                            .disabled(cli.isRunning)
                            Button("Cancel") { showUninstallConfirm = false }
                        }
                    }
                } else {
                    Button(role: .destructive) {
                        showUninstallConfirm = true
                    } label: {
                        Label("Uninstall Hermes...", systemImage: "trash")
                    }
                }
                if cli.isRunning { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 4)
        }
        .tint(.red)
    }

    // MARK: - CLI Output

    private var outputSection: some View {
        GroupBox(label: Label("Command Output", systemImage: "terminal")) {
            VStack(alignment: .leading, spacing: 8) {
                if !cli.output.isEmpty {
                    ScrollView {
                        Text(cli.output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100, maxHeight: 200)
                    Button { cli.clearOutput() } label: {
                        Label("Clear", systemImage: "xmark.circle").font(.caption)
                    }
                } else {
                    Text("Run a command above to see output here.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func refreshStatus() {
        configPreview = cli.readConfig()
    }

    private func statusRow(label: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color.green : Color.red.opacity(0.6)).frame(width: 6, height: 6)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
    }
}
