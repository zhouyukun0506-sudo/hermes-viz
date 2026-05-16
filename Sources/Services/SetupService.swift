import Foundation
import Combine

class SetupService: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var installError: String?

    private let home = NSHomeDirectory()
    private let hermesAgentDir: String
    private let hermesCLI: String
    private let installScriptURL = "https://hermes-agent.com/install.sh"
    private let repoURL = "https://github.com/NousResearch/hermes-agent.git"

    init() {
        hermesAgentDir = home + "/.hermes/hermes-agent"
        hermesCLI = home + "/.local/bin/hermes"
        checkInstallation()
    }

    func checkInstallation() {
        isInstalled = FileManager.default.fileExists(atPath: hermesCLI)
    }

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
                if !success && self.installError == nil { self.installError = "Installation failed." }
                completion(self.isInstalled)
            }
        }
    }

    private func performInstall() -> Bool {
        updateProgress("Trying official installer...")
        let (curlOut, curlCode) = runShell("curl -fsSL --connect-timeout 10 '\(installScriptURL)' 2>&1")
        if curlCode == 0, !curlOut.trimmingCharacters(in: .whitespaces).isEmpty {
            updateProgress("Running official installer...")
            let (_, installCode) = runShell("bash -c \"$(curl -fsSL '\(installScriptURL)')\" 2>&1")
            if installCode == 0, FileManager.default.fileExists(atPath: hermesCLI) {
                updateProgress("Official installer completed."); return true
            }
        }
        return performManualInstall()
    }

    private func performManualInstall() -> Bool {
        let fm = FileManager.default
        let pythonPath = autoResolvePython()
        guard let py = pythonPath else { return false }

        do { try fm.createDirectory(atPath: home + "/.hermes", withIntermediateDirectories: true) }
        catch { setError("Cannot create ~/.hermes"); return false }

        // Try offline bundle first
        if let offlineDir = findOfflineBundle() {
            updateProgress("Offline bundle found. Installing from local resources...")
            return performOfflineInstall(python: py, offlineDir: offlineDir)
        }

        if !ensureGit() { setError("git required"); return false }

        if !fm.fileExists(atPath: hermesAgentDir + "/.git") {
            updateProgress("Cloning hermes-agent...")
            try? fm.removeItem(atPath: hermesAgentDir)
            let (out, code) = runShell("git clone --depth 1 '\(repoURL)' '\(hermesAgentDir)' 2>&1")
            if code != 0 { setError("Clone failed:\n\(String(out.suffix(400)))"); return false }
        } else {
            _ = runShell("cd '\(hermesAgentDir)' && git pull --ff-only 2>&1")
        }

        let pipBin = hermesAgentDir + "/venv/bin/pip"
        if !fm.fileExists(atPath: pipBin) {
            try? fm.removeItem(atPath: hermesAgentDir + "/venv")
            updateProgress("Creating venv with system packages...")
            let (out, code) = runShell("cd '\(hermesAgentDir)' && '\(py)' -m venv venv --system-site-packages 2>&1")
            if code != 0 { setError("venv failed:\n\(String(out.suffix(300)))"); return false }
        }

        // Try offline install first (system site-packages provides setuptools)
        updateProgress("Installing hermes-agent (offline)...")
        let (_, offlineCode) = runShell("cd '\(hermesAgentDir)' && ./venv/bin/pip install --no-build-isolation -e . 2>&1")
        if offlineCode == 0 { return finalizeInstall() }

        // Fallback: with mirrors
        updateProgress("Offline install failed. Trying with mirrors...")
        if pipWithMirrors("install -e .") { return finalizeInstall() }
        if pipWithMirrors("install .") { return finalizeInstall() }

        setError("Cannot install hermes-agent.\n\nAll install methods failed.\nCheck network or try again.")
        return false
    }

    private func finalizeInstall() -> Bool {
        let fm = FileManager.default

        if !fm.fileExists(atPath: hermesCLI) {
            let (findOut, _) = runShell("find '\(hermesAgentDir)/venv/bin' -name 'hermes' -type f 2>/dev/null")
            let cli = findOut.trimmingCharacters(in: .whitespaces).components(separatedBy: "\n").first ?? ""
            if cli.isEmpty { setError("No hermes entry point found"); return false }
            try? fm.createDirectory(atPath: home + "/.local/bin", withIntermediateDirectories: true)
            try? fm.removeItem(atPath: hermesCLI)
            if runShell("ln -s '\(cli)' '\(hermesCLI)' 2>&1").exitCode != 0 {
                setError("Symlink failed"); return false
            }
        }
        _ = runShell("'\(hermesCLI)' postinstall 2>&1")
        return true
    }

    // MARK: - Offline Bundle

    /// Look for bundled offline resources inside the .app.
    private func findOfflineBundle() -> String? {
        // Bundled resources (SwiftPM)
        if let bundled = Bundle.module.resourcePath {
            let path = bundled + "/offline"
            if FileManager.default.fileExists(atPath: path + "/hermes-agent/pyproject.toml") {
                return path
            }
        }
        // Development: check alongside the binary
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("HermesViz.app/Contents/Resources/offline")
            .path
        if FileManager.default.fileExists(atPath: devPath + "/hermes-agent/pyproject.toml") {
            return devPath
        }
        return nil
    }

    private func performOfflineInstall(python: String, offlineDir: String) -> Bool {
        let fm = FileManager.default
        let wheelsDir = offlineDir + "/wheels"
        let srcDir = offlineDir + "/hermes-agent"

        // Copy source to ~/.hermes/
        updateProgress("Copying hermes-agent from bundle...")
        try? fm.removeItem(atPath: hermesAgentDir)
        do {
            try fm.copyItem(atPath: srcDir, toPath: hermesAgentDir)
        } catch {
            setError("Copy failed: \(error.localizedDescription)")
            return false
        }

        // Create venv
        updateProgress("Creating venv...")
        let (out, code) = runShell("cd '\(hermesAgentDir)' && '\(python)' -m venv venv --system-site-packages 2>&1")
        if code != 0 { setError("venv failed:\n\(String(out.suffix(300)))"); return false }

        // Install from local wheels (zero network)
        updateProgress("Installing from local wheels...")
        let installCmd = "cd '\(hermesAgentDir)' && ./venv/bin/pip install --no-index --find-links '\(wheelsDir)' --no-build-isolation -e . 2>&1"
        let (pipOut, pipCode) = runShell(installCmd)
        if pipCode != 0 {
            setError("Offline install failed:\n\(String(pipOut.suffix(500)))")
            return false
        }

        return finalizeInstall()
    }

    // MARK: - Python Resolution

    private func autoResolvePython() -> String? {
        // Try existing
        if let p = scanForPython() { updateProgress("Python \(extractVersion(p)) at \(p)"); return p }

        // Try brew install
        guard let brewPath = findHomebrew() else {
            setError("Homebrew not found.\nInstall: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\nThen Retry.")
            return nil
        }
        let brewDir = (brewPath as NSString).deletingLastPathComponent
        updateProgress("Installing Python via Homebrew...")
        _ = runShell("export PATH=\"\(brewDir):$PATH\" && brew install python@3.12 2>&1")

        if let p = scanForPython() { updateProgress("Python \(extractVersion(p))"); return p }
        setError("Python 3.11+ not found after brew install.\n\nCheck Terminal:\n  ls /opt/homebrew/bin/python3*\n\nThen Retry.")
        return nil
    }

    /// Exhaustive search for any Python >= 3.11.
    private func scanForPython() -> String? {
        // 1. Direct known paths sorted newest first
        let direct = [
            "/opt/homebrew/bin/python3.14", "/opt/homebrew/bin/python3.13",
            "/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3.11",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3.14", "/usr/local/bin/python3.13",
            "/usr/local/bin/python3.12", "/usr/local/bin/python3.11",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for p in direct {
            if FileManager.default.fileExists(atPath: p), isPy311(p) { return p }
        }

        // 2. brew --prefix for all python formulae
        if let brewPath = findHomebrew() {
            let brewDir = (brewPath as NSString).deletingLastPathComponent
            let brewEnv = "export PATH=\"\(brewDir):$PATH\""
            for formula in ["python@3.14","python@3.13","python@3.12","python@3.11","python3"] {
                let (prefix, code) = runShell("\(brewEnv) && brew --prefix \(formula) 2>/dev/null")
                if code != 0 { continue }
                let pfx = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                if pfx.isEmpty { continue }
                // List bin contents — find first python3.x >= 3.11
                let (lsOut, _) = runShell("ls '\(pfx)/bin/python3'* 2>/dev/null")
                for line in lsOut.components(separatedBy: "\n") {
                    let bin = line.trimmingCharacters(in: .whitespaces)
                    if !bin.isEmpty, isPy311(bin) { return bin }
                }
                // Also try libexec/bin (brew installs unversioned symlinks there)
                let (lsOut2, _) = runShell("ls '\(pfx)/libexec/bin/python3' 2>/dev/null")
                let libBin = lsOut2.trimmingCharacters(in: .whitespacesAndNewlines)
                if !libBin.isEmpty, isPy311(libBin) { return libBin }
            }
        }

        // 3. which python3.14 / 3.13 / 3.12 / 3.11 / python3
        for name in ["python3.14","python3.13","python3.12","python3.11","python3"] {
            let (path, code) = runShell("which \(name) 2>/dev/null")
            if code != 0 { continue }
            let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty, isPy311(p) { return p }
        }

        // 4. Broad filesystem scan
        let (findOut, _) = runShell("find /opt/homebrew /usr/local /usr/bin -maxdepth 5 -name 'python3*' -type f 2>/dev/null | head -20")
        for line in findOut.components(separatedBy: "\n") {
            let p = line.trimmingCharacters(in: .whitespaces)
            if !p.isEmpty, isPy311(p) { return p }
        }

        return nil
    }

    /// Run pip with proxy bypass + mirror fallbacks for restricted networks.
    private func pipWithMirrors(_ args: String) -> Bool {
        // Override macOS system proxy + any env vars (Python reads SystemConfiguration on macOS)
        let noProxy = "export HTTP_PROXY='' HTTPS_PROXY='' http_proxy='' https_proxy='' ALL_PROXY='' all_proxy='' no_proxy='*' 2>/dev/null; "

        let mirrors = [
            ("Tsinghua", "https://pypi.tuna.tsinghua.edu.cn/simple"),
            ("Aliyun",  "https://mirrors.aliyun.com/pypi/simple"),
            ("USTC",    "https://pypi.mirrors.ustc.edu.cn/simple"),
            ("default", ""),
        ]
        for (name, url) in mirrors {
            let mirrorArg = url.isEmpty ? "" : "-i \(url) --trusted-host \(URL(string: url)?.host ?? url)"
            let cmd = "\(noProxy) cd '\(hermesAgentDir)' && ./venv/bin/pip \(mirrorArg) --timeout 30 \(args) 2>&1"
            let (out, code) = runShell(cmd)
            if code == 0 { return true }
            let lower = out.lowercased()
            if lower.contains("tunnel connection failed")
                || lower.contains("service unavailable")
                || lower.contains("connection refused")
                || lower.contains("network is unreachable")
                || lower.contains("name or service not known")
                || lower.contains("timed out")
                || lower.contains("could not find a version") {
                updateProgress("Mirror \(name) unreachable, trying next...")
                continue
            }
            return false
        }

        // Last resort: try with --no-build-isolation (use venv's pip/setuptools directly)
        updateProgress("All mirrors failed. Trying --no-build-isolation...")
        let fallback = "\(noProxy) cd '\(hermesAgentDir)' && ./venv/bin/pip install --no-build-isolation --timeout 30 \(args) 2>&1"
        let (_, code) = runShell(fallback)
        return code == 0
    }

    private func isPy311(_ path: String) -> Bool {
        let (out, code) = runShell("'\(path)' -c 'import sys; print(sys.version_info.major,sys.version_info.minor)' 2>&1")
        guard code == 0 else { return false }
        let parts = out.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").compactMap { Int($0) }
        return parts.count >= 2 && (parts[0] > 3 || (parts[0] == 3 && parts[1] >= 11))
    }

    private func extractVersion(_ path: String) -> String {
        runShell("'\(path)' --version 2>&1").output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func findHomebrew() -> String? {
        for p in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        let (path, _) = runShell("which brew 2>/dev/null")
        let p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!p.isEmpty && FileManager.default.fileExists(atPath: p)) ? p : nil
    }

    private func ensureGit() -> Bool {
        if runShell("which git 2>/dev/null").exitCode == 0 { return true }
        guard let brew = findHomebrew() else { return false }
        let dir = (brew as NSString).deletingLastPathComponent
        _ = runShell("export PATH=\"\(dir):$PATH\" && brew install git 2>&1")
        return runShell("which git 2>/dev/null").exitCode == 0
    }

    private func updateProgress(_ t: String) { DispatchQueue.main.async { self.installProgress = t } }
    private func setError(_ t: String) { DispatchQueue.main.async { self.installError = t } }

    private func runShell(_ cmd: String) -> (output: String, exitCode: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do {
            try p.run(); p.waitUntilExit()
            let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (e.isEmpty ? o : o + "\n" + e, p.terminationStatus)
        } catch { return (error.localizedDescription, -1) }
    }
}
