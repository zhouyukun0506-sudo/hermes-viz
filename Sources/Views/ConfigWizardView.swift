import SwiftUI
import Yams

private struct HermesConfig: Codable {
    struct ModelConfig: Codable {
        let `default`: String
        let provider: String
        let api_key: String
        let base_url: String
        enum CodingKeys: String, CodingKey {
            case `default`, provider, api_key, base_url
        }
    }
    let model: ModelConfig
}

private struct ProviderPreset {
    let name: String; let label: String; let defaultModel: String; let defaultBaseURL: String
}

private let providers: [ProviderPreset] = [
    .init(name: "openai",     label: "OpenAI",     defaultModel: "gpt-4o",                   defaultBaseURL: "https://api.openai.com/v1"),
    .init(name: "anthropic",  label: "Anthropic",  defaultModel: "claude-sonnet-4-20250514", defaultBaseURL: "https://api.anthropic.com/v1"),
    .init(name: "openrouter", label: "OpenRouter", defaultModel: "openai/gpt-4o",            defaultBaseURL: "https://openrouter.ai/api/v1"),
    .init(name: "groq",       label: "Groq",       defaultModel: "llama-3.3-70b-versatile", defaultBaseURL: "https://api.groq.com/openai/v1"),
    .init(name: "custom",     label: "Custom",     defaultModel: "",                        defaultBaseURL: ""),
]

struct ConfigWizardView: View {
    @State private var apiKey: String = ""
    @State private var baseUrl: String = providers[0].defaultBaseURL
    @State private var model: String = providers[0].defaultModel
    @State private var provider: String = "openai"
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var didSave = false

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if didSave {
                savedView
            } else {
                formView
            }
        }
        .padding(40)
        .frame(maxWidth: 450)
        .background(Color.wxBase)
        .animation(.easeInOut(duration: 0.3), value: didSave)
    }

    private var savedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48)).foregroundStyle(.green)
            Text("Configuration Saved")
                .font(.title3.bold())
            Text("Loading your dashboard…")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                onComplete()
            }
        }
    }

    private var formView: some View {
        VStack(spacing: 24) {
            Text("Model Configuration").font(.system(size: 20, weight: .bold))

            VStack(alignment: .leading, spacing: 16) {
                // Provider
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Provider").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $provider) {
                        ForEach(providers, id: \.name) { p in Text(p.label).tag(p.name) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) { _, new in
                        if let p = providers.first(where: { $0.name == new }) {
                            model = p.defaultModel; baseUrl = p.defaultBaseURL
                        }
                        saveError = nil
                    }
                }

                // Model
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model Name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. gpt-4o", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model) { _, _ in saveError = nil }
                }

                // API Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key").font(.caption).foregroundStyle(.secondary)
                    SecureField("Paste your key here", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, _ in saveError = nil }
                }

                // Base URL
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL").font(.caption).foregroundStyle(.secondary)
                    TextField("https://api.openai.com/v1", text: $baseUrl)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: baseUrl) { _, _ in saveError = nil }
                }

                // Error
                if let error = saveError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    .padding(10).background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
            .background(Color.wxSurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if isSaving {
                ProgressView("Saving configuration…")
            } else {
                Button(action: saveConfig) {
                    Text("Save & Start Chatting")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(
                            apiKey.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.gray.opacity(0.4) : Color.wxAccent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }

    func saveConfig() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)

        guard !trimmedKey.isEmpty else { saveError = "API Key is required."; return }
        guard !trimmedModel.isEmpty else { saveError = "Model name is required."; return }

        isSaving = true
        saveError = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let hermesDir = NSHomeDirectory() + "/.hermes"
            let configPath = hermesDir + "/config.yaml"

            do {
                if !FileManager.default.fileExists(atPath: hermesDir) {
                    try FileManager.default.createDirectory(atPath: hermesDir, withIntermediateDirectories: true)
                }
            } catch {
                DispatchQueue.main.async { isSaving = false; saveError = "Cannot create directory: \(error.localizedDescription)" }
                return
            }

            let config = HermesConfig(model: .init(
                default: trimmedModel, provider: provider,
                api_key: trimmedKey, base_url: baseUrl.trimmingCharacters(in: .whitespaces)
            ))

            do {
                try YAMLEncoder().encode(config).write(toFile: configPath, atomically: true, encoding: .utf8)
                DispatchQueue.main.async { isSaving = false; didSave = true }
            } catch {
                DispatchQueue.main.async { isSaving = false; saveError = "Failed to save: \(error.localizedDescription)" }
            }
        }
    }
}
