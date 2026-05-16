import SwiftUI

struct OnboardingView: View {
    @ObservedObject var setup: SetupService
    @State private var showingConfig = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Logo / Icon
            Circle()
                .fill(Color.wxAccent)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.wxAccent.opacity(0.3), radius: 20)
            
            VStack(spacing: 8) {
                Text("Welcome to Hermes")
                    .font(.system(size: 24, weight: .bold))
                Text("Professional AI Agent Interface")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            
            if setup.isInstalling {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text(setup.installProgress)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if let error = setup.installError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.title)
                    Text("Installation Failed")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry Installation") {
                        setup.install { _ in }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.top, 10)
                }
            } else {
                VStack(spacing: 20) {
                    FeatureRow(icon: "sparkles", title: "Autonomous Agent", description: "Powered by Hermes-Agent for complex tool use.")
                    FeatureRow(icon: "doc.text.magnifyingglass", title: "Multi-modal Analysis", description: "Deep analysis of PDFs, images, and codebases.")
                    FeatureRow(icon: "shield.check", title: "Local Privacy", description: "Run with local LLMs or secure API bridges.")
                    
                    Spacer()
                        .frame(height: 20)
                    
                    Button {
                        setup.install { success in
                            if success {
                                // Transition to config or main app
                            }
                        }
                    } label: {
                        Text("Setup Hermes Agent")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 220, height: 44)
                            .background(Color.wxAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    
                    Text("This will download ~100MB of backend components.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: 400)
        .background(Color.wxBase)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.wxAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
