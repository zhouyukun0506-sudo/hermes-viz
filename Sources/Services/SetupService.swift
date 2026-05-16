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

        // Resolve a Python >= 3.11, auto-install if missing
        let pythonPath = autoResolvePython()
        if pythonPath == nil {
            if findHomebrew() != nil {
                setError("Python 3.11+ installation failed.\n\nThe brew install command did not complete successfully.\n\nPlease run in Terminal:\n  brew install python@3.12\n\nThen click Retry.")
            } else {
                setError("Python 3.11+ and Homebrew not found.\n\nInstall Homebrew first:\n  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n\nThen click Retry to auto-install Python.")
            }
            return false
        }

        do {
            try fm.createDirectory(atPath: hermesBase, withIntermediateDirectories: true)
        } catch {
            setError("Cannot create ~/.hermes: \(error.localizedDescription)")
            return false
        }

        // Ensure git is available
        if !ensureGit() {
            setError("git is required but could not be installed.\n\nInstall manually:\n  brew install git\n  or download from https://git-scm.com")
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
            let (venvOut, venvCode) = runShell("cd '\(hermesAgentDir)' && '\(pythonPath!)' -m venv venv 2>&1")
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

    // MARK: - Python Resolution

    /// Find a Python >= 3.11. If not found, auto-install via Homebrew if brew is available.
    /// Returns the path to a suitable Python, or nil.
    private func autoResolvePython() -> String? {
        // 1. Try existing installations (including Homebrew's opt paths)
        if let existing = scanForPython() {
            updateProgress("Python \(extractPythonVersion(existing)) found at \(existing)")
            return existing
        }

        // 2. Locate Homebrew (or give clear instructions)
        updateProgress("Python 3.11+ not found.")
        guard let brewPath = findHomebrew() else {
            updateProgress("Homebrew not found. To install:")
            updateProgress("  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
            updateProgress("Then click Retry.")
            return nil
        }

        // 3. Auto-install Python via Homebrew
        let brewBinDir = (brewPath as NSString).deletingLastPathComponent
        let brewEnv = "export PATH=\"\(brewBinDir):$PATH\""
        updateProgress("Installing Python 3.12 via Homebrew (this may take a few minutes)...")
        let (brewOut, brewCode) = runShell("\(brewEnv) && brew install python@3.12 2>&1")
        if brewCode == 0 {
            updateProgress("Python 3.12 installed. Rescanning...")
        } else {
            updateProgress("brew install returned code \(brewCode). Checking if Python is now available...")
        }

        // 4. Rescan with expanded paths (include brew opt directories)
        if let installed = scanForPython(includeOptPaths: true) {
            updateProgress("Using Python at \(installed)")
            return installed
        }

        updateProgress("Python still not found after brew install.")
        return nil
    }

    /// Scan for any Python >= 3.11 on the system.
    private func scanForPython(includeOptPaths: Bool = false) -> String? {
        var candidates = [
            "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.12",
            "/opt/homebrew/bin/python3.11",
            "/usr/local/bin/python3.11",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        if includeOptPaths {
            candidates.append(contentsOf: [
                "/opt/homebrew/opt/python@3.12/bin/python3.12",
                "/opt/homebrew/opt/python@3.13/bin/python3.13",
                "/opt/homebrew/opt/python@3.11/bin/python3.11",
                "/usr/local/opt/python@3.12/bin/python3.12",
                "/usr/local/opt/python@3.11/bin/python3.11",
            ])
        }
        for path in candidates {
            if FileManager.default.fileExists(atPath: path), checkPythonVersion(path) {
                return path
            }
        }
        // Try PATH
        for bin in ["python3.12", "python3.11", "python3"] {
            let (whichOut, _) = runShell("which \(bin) 2>/dev/null")
            let whichPath = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !whichPath.isEmpty, FileManager.default.fileExists(atPath: whichPath), checkPythonVersion(whichPath) {
                return whichPath
            }
        }
        return nil
    }

    /// Locate the Homebrew binary. Returns the path, or nil.
    private func findHomebrew() -> String? {
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/home/linuxbrew/.linuxbrew/bin/brew"]
        for p in brewPaths {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        let (whichOut, _) = runShell("which brew 2>/dev/null")
        let whichBrew = whichOut.trimmingCharacters(in: .whitespacesAndNewlines)
        if !whichBrew.isEmpty, FileManager.default.fileExists(atPath: whichBrew) { return whichBrew }
        return nil
    }

    /// Check if the Python at `path` is >= 3.11.
    private func checkPythonVersion(_ path: String) -> Bool {
        let (versionOut, code) = runShell("'\(path)' -c 'import sys; print(sys.version_info.major, sys.version_info.minor)' 2>&1")
        guard code == 0 else { return false }
        let parts = versionOut.split(separator: " ")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return false }
        return major > 3 || (major == 3 && minor >= 11)
    }

    private func extractPythonVersion(_ path: String) -> String {
        let (v, _) = runShell("'\(path)' --version 2>&1")
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Git Resolution

    /// Ensure git is installed. Tries to auto-install via brew if missing.
    private func ensureGit() -> Bool {
        let (_, code) = runShell("which git 2>/dev/null")
        if code == 0 { return true }

        updateProgress("git not found. Attempting to install...")
        if let brewPath = findHomebrew() {
            let brewBinDir = (brewPath as NSString).deletingLastPathComponent
            let brewEnv = "export PATH=\"\(brewBinDir):$PATH\""
            let (_, gitCode) = runShell("\(brewEnv) && brew install git 2>&1")
            if gitCode == 0 {
                updateProgress("git installed via Homebrew.")
                return true
            }
        }
        return false
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
