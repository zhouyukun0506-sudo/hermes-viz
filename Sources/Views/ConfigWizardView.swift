import SwiftUI

struct ConfigWizardView: View {
    @State private var apiKey: String = ""
    @State private var baseUrl: String = "https://api.openai.com/v1"
    @State private var model: String = "gpt-4o"
    @State private var provider: String = "openai"
    @State private var isSaving = false
    @State private var showSuccess = false
    
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Model Configuration")
                .font(.system(size: 20, weight: .bold))
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Provider")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $provider) {
                        Text("OpenAI").tag("openai")
                        Text("Anthropic").tag("anthropic")
                        Text("OpenRouter").tag("openrouter")
                        Text("Groq").tag("groq")
                        Text("Custom").tag("custom")
                    }
                    .pickerStyle(.segmented)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model Name")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. gpt-4o, claude-3-5-sonnet", text: $model)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("Paste your key here", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL (Optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("https://api.openai.com/v1", text: $baseUrl)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
            .background(Color.wxSurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if isSaving {
                ProgressView()
            } else {
                Button {
                    saveConfig()
                } label: {
                    Text("Save & Start Chatting")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.wxAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(40)
        .frame(maxWidth: 450)
        .background(Color.wxBase)
    }
    
    func saveConfig() {
        isSaving = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let configPath = NSHomeDirectory() + "/.hermes/config.yaml"
            let yaml = """
            model:
              default: "\(model)"
              provider: "\(provider)"
              api_key: "\(apiKey)"
              base_url: "\(baseUrl)"
            """
            
            do {
                try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    isSaving = false
                    onComplete()
                }
            } catch {
                DispatchQueue.main.async {
                    isSaving = false
                    // Handle error
                }
            }
        }
    }
}
