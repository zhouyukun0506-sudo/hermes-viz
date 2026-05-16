import Foundation
import Combine

/// Handles Hermes Agent installation via official installer script.
/// Uses: curl -fsSL https://hermes-agent.com/install.sh | bash
/// Falls back to manual git clone + venv + pip if the installer is unreachable.
class SetupService: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var installError: String?

    private let home = NSHomeDirectory()
    private let hermesAgentDir: String
    private let hermesCLI: String
    private let venvPython: String
    private let installScriptURL = "https://hermes-agent.com/install.sh"
    private let repoURL = "https://github.com/NousResearch/hermes-agent.git"

    init() {
        hermesAgentDir = home + "/.hermes/hermes-agent"
        hermesCLI = home + "/.local/bin/hermes"
        venvPython = hermesAgentDir + "/venv/bin/python3"
        checkInstallation()
    }

    /// Verify hermes CLI binary exists.
    func checkInstallation() {
        isInstalled = FileManager.default.fileExists(atPath: hermesCLI)
    }

    // MARK: - Install

    func install(completion: @escaping (Bool) -> Void) {
        isInstalling = true
        installError = nil
        installProgress = "Checking environment..."

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let success = self.performInstall()
            DispatchQueue.main.async {
                self.isInstalling = false
                self.checkInstallation()
                if !success && self.installError == nil {
                    self.installError = "Installation failed. Check the console output for details."
                }
                completion(self.isInstalled)
            }
        }
    }

    private func performInstall() -> Bool {
        // Strategy 1: Try official installer
        updateProgress("Trying official installer...")
        let (curlOut, curlCode) = runShell("curl -fsSL --connect-timeout 10 '\(installScriptURL)' 2>&1")
        if curlCode == 0 && !curlOut.trimmingCharacters(in: .whitespaces).isEmpty {
            updateProgress("Running official installer...")
            let (_, installCode) = runShell("bash -c \"$(curl -fsSL '\(installScriptURL)')\" 2>&1")
            if installCode == 0, FileManager.default.fileExists(atPath: hermesCLI) {
                updateProgress("Official installer completed.")
                return true
            }
            updateProgress("Official installer did not produce hermes CLI. Falling back to manual setup...")
        } else {
            updateProgress("Official installer not reachable. Using manual setup...")
        }

        // Strategy 2: Manual install
        return performManualInstall()
    }

    private func performManualInstall() -> Bool {
        let fm = FileManager.default
        let hermesBase = home + "/.hermes"

        do {
            try fm.createDirectory(atPath: hermesBase, withIntermediateDirectories: true)
        } catch {
            setError("Cannot create ~/.hermes: \(error.localizedDescription)")
            return false
        }

        // Clone
        if !fm.fileExists(atPath: hermesAgentDir + "/.git") {
            updateProgress("Cloning hermes-agent...")
            try? fm.removeItem(atPath: hermesAgentDir)
            let (cloneOut, cloneCode) = runShell("git clone --depth 1 '\(repoURL)' '\(hermesAgentDir)' 2>&1")
            if cloneCode != 0 {
                let tail = String(cloneOut.suffix(400))
                setError("Failed to clone:\n\(tail)")
                return false
            }
            updateProgress("Cloned.")
        } else {
            updateProgress("Repository exists, updating...")
            _ = runShell("cd '\(hermesAgentDir)' && git pull --ff-only 2>&1")
        }

        // Venv — always recreate if pip is missing
        let pipPath = hermesAgentDir + "/venv/bin/pip"
        if !fm.fileExists(atPath: pipPath) {
            if fm.fileExists(atPath: hermesAgentDir + "/venv") {
                updateProgress("Removing incomplete venv...")
                try? fm.removeItem(atPath: hermesAgentDir + "/venv")
            }
            updateProgress("Creating venv...")
            let (venvOut, venvCode) = runShell("cd '\(hermesAgentDir)' && python3 -m venv venv 2>&1")
            if venvCode != 0 {
                let tail = String(venvOut.suffix(300))
                setError("venv creation failed. Is python3 installed?\n\(tail)")
                return false
            }
        }

        // Upgrade pip first (old pip can't handle pyproject.toml editable installs)
        updateProgress("Upgrading pip...")
        let (upgradeOut, upgradeCode) = runShell("cd '\(hermesAgentDir)' && ./venv/bin/pip install --upgrade pip setuptools wheel 2>&1")
        if upgradeCode != 0 {
            updateProgress("pip upgrade had warnings (non-fatal).")
        } else {
            updateProgress("pip upgraded.")
        }

        // Pip install — always run to ensure latest
        updateProgress("Installing hermes-agent (this may take a minute)...")
        let (pipOut, pipCode) = runShell("cd '\(hermesAgentDir)' && ./venv/bin/pip install -e . 2>&1")
        if pipCode != 0 {
            // Fallback: try non-editable install (some build backends don't support -e)
            updateProgress("Editable install failed. Trying regular install...")
            let (pipOut2, pipCode2) = runShell("cd '\(hermesAgentDir)' && ./venv/bin/pip install . 2>&1")
            if pipCode2 != 0 {
                let tail = String(pipOut2.suffix(500))
                setError("pip install failed:\n\(tail)")
                return false
            }
            updateProgress("Package installed (non-editable).")
        }

        // Verify hermes CLI was created
        if !fm.fileExists(atPath: hermesCLI) {
            let (findOut, _) = runShell("find '\(hermesAgentDir)/venv/bin' -name 'hermes' -type f 2>/dev/null")
            let bins = findOut.trimmingCharacters(in: .whitespaces)
            if !bins.isEmpty {
                updateProgress("Creating symlink...")
                let binDir = home + "/.local/bin"
                try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
                try? fm.removeItem(atPath: hermesCLI)
                let cliPath = bins.components(separatedBy: "\n").first ?? ""
                let (_, lnCode) = runShell("ln -s '\(cliPath)' '\(hermesCLI)' 2>&1")
                if lnCode != 0 {
                    setError("Symlink failed. Run: ln -s \(cliPath) \(hermesCLI)")
                    return false
                }
            } else {
                setError("pip completed but no 'hermes' entry point found.")
                return false
            }
        }

        // Postinstall
        updateProgress("Running postinstall...")
        let (postOut, postCode) = runShell("'\(hermesCLI)' postinstall 2>&1")
        if postCode != 0 {
            updateProgress("Postinstall warnings (non-fatal).")
        } else {
            updateProgress("Postinstall done.")
        }

        return true
    }

    // MARK: - Helpers

    private func updateProgress(_ text: String) {
        DispatchQueue.main.async { self.installProgress = text }
    }

    private func setError(_ text: String) {
        DispatchQueue.main.async { self.installError = text }
    }

    private func runShell(_ command: String) -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let outStr = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            var output = outStr
            if !errStr.isEmpty { output += "\n\(errStr)" }
            return (output, process.terminationStatus)
        } catch {
            return (error.localizedDescription, -1)
        }
    }
}
