import Foundation
import Combine

class SetupService: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var installProgress: String = ""
    @Published var installError: String?
    
    private let hermesDir = NSHomeDirectory() + "/.hermes/hermes-agent"
    private let venvPython = NSHomeDirectory() + "/.hermes/hermes-agent/venv/bin/python3"
    
    init() {
        checkInstallation()
    }
    
    func checkInstallation() {
        isInstalled = FileManager.default.fileExists(atPath: venvPython)
    }
    
    func install(completion: @escaping (Bool) -> Void) {
        isInstalling = true
        installProgress = "Preparing directories..."
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let hermesBase = NSHomeDirectory() + "/.hermes"
                if !FileManager.default.fileExists(atPath: hermesBase) {
                    try FileManager.default.createDirectory(atPath: hermesBase, withIntermediateDirectories: true)
                }
                
                if !FileManager.default.fileExists(atPath: self.hermesDir) {
                    updateProgress("Cloning hermes-agent...")
                    let cloneResult = runShell("git clone https://github.com/NousResearch/hermes-agent.git '\(self.hermesDir)'")
                    if cloneResult != 0 {
                        throw NSError(domain: "Setup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to clone repository"])
                    }
                }
                
                if !FileManager.default.fileExists(atPath: self.venvPython) {
                    updateProgress("Creating virtual environment...")
                    let venvResult = runShell("cd '\(self.hermesDir)' && python3 -m venv venv")
                    if venvResult != 0 {
                        throw NSError(domain: "Setup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create venv"])
                    }
                    
                    updateProgress("Installing dependencies (this may take a minute)...")
                    let pipResult = runShell("cd '\(self.hermesDir)' && ./venv/bin/pip install -e .")
                    if pipResult != 0 {
                        throw NSError(domain: "Setup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to install dependencies"])
                    }
                }
                
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.isInstalled = true
                    completion(true)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    self.installError = error.localizedDescription
                    completion(false)
                }
            }
        }
    }
    
    private func updateProgress(_ text: String) {
        DispatchQueue.main.async {
            self.installProgress = text
        }
    }
    
    private func runShell(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        // Hide output
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
