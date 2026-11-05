import SwiftUI

struct TagChip: View {
    let name: String
    let color: Color
    var compact = false
    var onRemove: (() -> Void)?

    var body: some View {
        GrokChip(title: name, style: .tinted(color), size: compact ? .compact : .regular, onRemove: onRemove)
    }
}

/// Lays subviews out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = GrokSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// Tag chips plus add and suggest controls for the meeting inspector.
struct MeetingTagsEditor: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    let meetingID: UUID
    @State private var newTag = ""

    var body: some View {
        let tags = state.meeting(meetingID)?.tagList ?? []
        if tags.isEmpty {
            Text("No tags yet.")
                .font(.callout)
                .foregroundStyle(GrokColors.inkMuted)
        } else {
            FlowLayout {
                ForEach(tags, id: \.self) { tag in
                    TagChip(name: tag, color: catalog.color(for: tag)) {
                        state.removeTag(tag, from: meetingID)
                    }
                }
            }
        }
        HStack(spacing: GrokSpacing.sm) {
            TextField("Add tag", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            let available = catalog.tags.filter { tag in !tags.contains { $0.caseInsensitiveCompare(tag.name) == .orderedSame } }
            Menu {
                ForEach(available.filter { !$0.isDynamic }) { tag in
                    Button(tag.name) { state.addTag(tag.name, to: meetingID) }
                }
                let dynamic = available.filter(\.isDynamic)
                if !dynamic.isEmpty {
                    Section("Suggested by Grok") {
                        ForEach(dynamic) { tag in
                            Button(tag.name) { state.addTag(tag.name, to: meetingID) }
                        }
                    }
                }
            } label: {
                Image(systemName: "tag")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(available.isEmpty)
            .help("Pick a tag from your catalog")
        }
        HStack {
            Button("Suggest tags") { Task { await state.suggestTags(meetingID) } }
                .disabled(catalog.tagging.contains(meetingID) || state.processing.contains(meetingID))
            if catalog.tagging.contains(meetingID) {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func add() {
        state.addTag(newTag, to: meetingID)
        newTag = ""
    }
}

/// Settings: the tag catalog, Grok's dynamic tags, and the backfill.
struct TagSettingsSection: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    @AppStorage("autoTag") private var autoTag = true
    @AppStorage("dynamicTags") private var dynamicTags = true
    @State private var newName = ""
    @State private var newDetail = ""
    @State private var confirmBackfill = false

    var body: some View {
        let counts = state.usageCounts()
        Section("Tags") {
            Toggle("Tag meetings automatically when notes are written", isOn: $autoTag)
            Toggle("Let Grok create new tags", isOn: $dynamicTags)
            Text("Grok prefers your tags and follows their descriptions. New tags it creates appear under Suggested by Grok until you keep or delete them.")
                .font(.caption)
                .foregroundStyle(GrokColors.inkMuted)

            ForEach(catalog.userTags) { tag in
                TagEditRow(tag: tag, count: counts[tag.name.lowercased()] ?? 0)
            }
            HStack {
                TextField("New tag", text: $newName)
                    .frame(maxWidth: 140)
                TextField("When it applies (optional)", text: $newDetail)
                    .onSubmit(addTag)
                Button("Add", action: addTag)
                    .disabled(TagCatalog.clean(newName).isEmpty)
            }
            .textFieldStyle(.roundedBorder)
        }

        if !catalog.dynamicTags.isEmpty {
            Section("Suggested by Grok") {
                ForEach(catalog.dynamicTags) { tag in
                    HStack {
                        TagChip(name: tag.name, color: tag.displayColor)
                        Text("\(counts[tag.name.lowercased()] ?? 0) meetings")
                            .font(.caption)
                            .foregroundStyle(GrokColors.inkMuted)
                        Spacer()
                        Button("Keep") { catalog.keep(tag.id) }
                        Button("Delete", role: .destructive) { state.deleteTag(tag.id) }
                    }
                }
            }
        }

        Section("Tag existing meetings") {
            let untagged = state.untaggedMeetings.count
            if let progress = catalog.backfill {
                HStack {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text("\(progress.done) of \(progress.total)").monospacedDigit()
                    Button("Cancel") { catalog.backfillCancelled = true }
                }
            } else {
                HStack {
                    Button("Tag all untagged meetings") { confirmBackfill = true }
                        .disabled(untagged == 0 || (!dynamicTags && catalog.tags.isEmpty))
                    Text(untagged == 0 ? "Every meeting has tags." : "\(untagged) untagged")
                        .foregroundStyle(GrokColors.inkMuted)
                }
            }
            Text("Sends each meeting's notes to Grok, one at a time. Existing tags are kept.")
                .font(.caption)
                .foregroundStyle(GrokColors.inkMuted)
        }
        .confirmationDialog("Tag \(state.untaggedMeetings.count) meetings?", isPresented: $confirmBackfill) {
            Button("Tag meetings") { Task { await state.tagAllUntagged() } }
        } message: {
            Text("This makes one xAI request per meeting, about \(state.estimatedBackfillCost().usd) in total. You can cancel at any time.")
        }
    }

    private func addTag() {
        guard !TagCatalog.clean(newName).isEmpty else { return }
        catalog.register(newName, dynamic: false, detail: newDetail.trimmingCharacters(in: .whitespacesAndNewlines))
        newName = ""
        newDetail = ""
    }
}

private struct TagEditRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    let tag: TagDefinition
    let count: Int
    @State private var name = ""
    @State private var detail = ""
    @FocusState private var nameFocused: Bool
    @State private var confirmDelete = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Menu {
                Button("Automatic") { catalog.setColor(tag.id, nil) }
                Divider()
                ForEach(TagColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) { catalog.setColor(tag.id, color) }
                }
            } label: {
                Circle().fill(tag.displayColor).frame(width: 10, height: 10)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Tag color")

            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .fontWeight(.medium)
                TextField("When it applies (optional)", text: $detail)
                    .font(.caption)
                    .foregroundStyle(GrokColors.inkMuted)
                    .onChange(of: detail) { catalog.setDetail(tag.id, detail) }
            }
            .textFieldStyle(.plain)
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(GrokColors.inkMuted)
                .help("Meetings with this tag")
            Button {
                if count > 0 { confirmDelete = true } else { state.deleteTag(tag.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete tag")
        }
        .onAppear {
            name = tag.name
            detail = tag.detail ?? ""
        }
        .onChange(of: nameFocused) {
            if !nameFocused { commitName() }
        }
        .confirmationDialog("Delete “\(tag.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { state.deleteTag(tag.id) }
        } message: {
            Text("It will be removed from \(count) meetings.")
        }
    }

    private func commitName() {
        let clean = TagCatalog.clean(name)
        if clean.isEmpty || clean == tag.name {
            name = tag.name
        } else {
            state.renameTag(tag.id, to: clean)
        }
    }
}
