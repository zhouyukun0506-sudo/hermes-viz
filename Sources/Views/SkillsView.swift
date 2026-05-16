import SwiftUI

struct SkillsView: View {
    @State private var service = HermesDataService.shared
    @State private var searchText = ""

    private var filtered: [SkillItem] {
        if searchText.isEmpty { return service.skills }
        return service.skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.desc.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedSkills: [(category: String, skills: [SkillItem])] {
        var groups: [String: [SkillItem]] = [:]
        for skill in filtered {
            let cat = categoryFor(skill.name)
            groups[cat, default: []].append(skill)
        }
        return groups.map { (category: $0.key, skills: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skills")
                        .font(.largeTitle.bold())
                    Text("\(service.skills.count) installed skills")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search skills...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 160)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            if service.skills.isEmpty {
                ContentUnavailableView(
                    "No Installed Skills",
                    systemImage: "star.slash",
                    description: Text("Skills are created automatically from agent experience")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedSkills, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(group.category)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 4)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ], spacing: 12) {
                                    ForEach(group.skills) { skill in
                                        SkillCard(skill: skill)
                                    }
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Color.wxBase)
    }

    private func categoryFor(_ name: String) -> String {
        if name.contains("github") || name.contains("pr-") || name.contains("code-review") { return "GitHub" }
        if name.contains("docker") || name.contains("deploy") || name.contains("kanban") { return "DevOps" }
        if name.contains("obsidian") || name.contains("notes") || name.contains("study") { return "Notes & Study" }
        if name.contains("youtube") || name.contains("music") || name.contains("song") { return "Media" }
        if name.contains("calendar") || name.contains("airtable") || name.contains("notion") || name.contains("linear") { return "Productivity" }
        if name.contains("hugging") || name.contains("llama") || name.contains("axolotl") || name.contains("ml") || name.contains("model") { return "ML/AI" }
        if name.contains("hermes") || name.contains("codex") || name.contains("claude") { return "Agent Tools" }
        if name.contains("apple") || name.contains("macos") || name.contains("findmy") || name.contains("imessage") { return "Apple" }
        return "General"
    }
}

struct SkillCard: View {
    let skill: SkillItem
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: skillIcon)
                    .font(.title3)
                    .foregroundStyle(skillColor)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }

            Text(skill.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            if !skill.desc.isEmpty {
                Text(skill.desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Text(skillPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(Color.wxSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.08 : 0.03), radius: 4, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var skillIcon: String {
        let n = skill.name.lowercased()
        if n.contains("github") || n.contains("pr") { return "chevron.left.forwardslash.chevron.right" }
        if n.contains("code") || n.contains("debug") { return "wrench.and.screwdriver" }
        if n.contains("note") || n.contains("obsidian") || n.contains("study") { return "note.text" }
        if n.contains("search") || n.contains("arxiv") || n.contains("research") { return "magnifyingglass" }
        if n.contains("music") || n.contains("song") || n.contains("audio") { return "music.note" }
        if n.contains("youtube") || n.contains("video") { return "play.rectangle.fill" }
        if n.contains("mail") || n.contains("email") { return "envelope.fill" }
        if n.contains("calendar") { return "calendar" }
        if n.contains("design") || n.contains("diagram") || n.contains("sketch") { return "paintbrush" }
        if n.contains("deploy") || n.contains("docker") || n.contains("ci") { return "cloud.fill" }
        if n.contains("hermes") || n.contains("agent") { return "bolt.fill" }
        if n.contains("apple") || n.contains("imessage") || n.contains("macos") { return "apple.logo" }
        if n.contains("test") || n.contains("tdd") { return "checkmark.shield" }
        return "star.fill"
    }

    private var skillColor: Color {
        let n = skill.name.lowercased()
        if n.contains("github") || n.contains("code") { return .blue }
        if n.contains("note") || n.contains("obsidian") || n.contains("study") { return .purple }
        if n.contains("search") || n.contains("research") { return .cyan }
        if n.contains("music") || n.contains("song") { return .pink }
        if n.contains("design") || n.contains("diagram") { return .orange }
        if n.contains("hermes") || n.contains("agent") { return .green }
        if n.contains("apple") { return .gray }
        return .secondary
    }

    private var skillPath: String {
        let parts = skill.path.components(separatedBy: "/")
        if let idx = parts.lastIndex(of: "skills") {
            return parts[(idx + 1)...].joined(separator: "/")
        }
        return skill.path
    }
}
