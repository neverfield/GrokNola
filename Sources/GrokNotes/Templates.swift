import Foundation

/// How Grok writes the enhanced notes for one kind of meeting.
struct SummaryTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// SF Symbol name.
    var icon: String
    /// What to focus on and how to write.
    var instructions: String
    /// Ordered "## " headings. Empty sections are left out.
    var sections: [String]
    /// What counts as a topic for this kind of meeting.
    var topicFocus: String
    var builtIn: Bool

    static let generalID = "general"

    static let builtIns: [SummaryTemplate] = [
        SummaryTemplate(
            id: generalID,
            name: "General meeting",
            icon: "doc.text",
            instructions: """
            Write balanced notes that someone who missed the meeting can read in two minutes. \
            Summary: 2 to 4 sentences on the purpose of the meeting and what came out of it. \
            Key points by topic: one "### " subheading per subject discussed, with short bullets of what was said, the reasoning, and any numbers or dates. \
            Decisions: only what the group actually agreed, not ideas that were floated. \
            Open questions: what was raised but not settled.
            """,
            sections: ["Summary", "Key points by topic", "Decisions", "Action items", "Open questions"],
            topicFocus: "the subjects the group spent time on, such as a project, a process, a plan, or a problem.",
            builtIn: true
        ),
        SummaryTemplate(
            id: "customer",
            name: "Customer / sales call",
            icon: "person.crop.circle.badge.checkmark",
            instructions: """
            This is a call with a customer or prospect. Write it for an account team that needs to act on it. \
            Context: who the customer is, who attended on their side and their roles, and where the deal or relationship stands. \
            Their needs & pain points: their problems and goals in their own terms; keep short direct quotes when they are telling. \
            Objections & concerns: every hesitation about price, security, timing, competitors, or fit, and how it was answered (or that it was not). \
            What we committed: promises our side made (demos, pricing, features, follow-up material), with owner. \
            Next steps: agreed actions on both sides, with owner and date. \
            Deal signals: buying signals and risks, budget, authority, timeline, competitors mentioned, and champions. \
            Separate what the customer said from what our side said.
            """,
            sections: ["Context", "Their needs & pain points", "Objections & concerns", "What we committed", "Next steps", "Deal signals"],
            topicFocus: "customer needs, product areas, and commercial subjects, such as \"Pricing and Packaging\", \"Security Review\", \"Data Migration\", or \"Competitive Evaluation\".",
            builtIn: true
        ),
        SummaryTemplate(
            id: "one-on-one",
            name: "1:1",
            icon: "person.2",
            instructions: """
            This is a one-on-one between two people, often a manager and a report. Keep a warm, private, candid tone and write in plain language. \
            Updates: what each person shared about their work, briefly. \
            Feedback (both ways): feedback given in either direction, who gave it to whom, and the specific example behind it. \
            Blockers: what is slowing the person down and what help was offered. \
            Goals & growth: career goals, skills to build, and progress against earlier goals. \
            Action items: commitments from either person. \
            Capture feelings and concerns accurately without dramatizing them.
            """,
            sections: ["Updates", "Feedback (both ways)", "Blockers", "Goals & growth", "Action items"],
            topicFocus: "the work areas and personal-development subjects discussed, such as \"Project Handoff\", \"Promotion Readiness\", \"Workload Balance\", or \"Team Communication\".",
            builtIn: true
        ),
        SummaryTemplate(
            id: "standup",
            name: "Standup / team sync",
            icon: "person.3",
            instructions: """
            This is a recurring team standup or sync. Be terse; the team reads this at a glance. \
            Updates by person: one "### " subheading per person who gave an update, named by speaker, each with "- Yesterday:", "- Today:", and "- Blockers:" bullets. \
            Leave out a bullet the person did not cover, and write "Blockers: none" only when they said so. Use "Them" updates under "### Others" when the speaker is unidentified. \
            Decisions: anything the team settled during the sync. \
            Follow-ups: conversations taken offline and who needs to talk to whom. \
            Skip small talk entirely.
            """,
            sections: ["Updates by person", "Decisions", "Follow-ups"],
            topicFocus: "the workstreams, projects, or incidents the team reported on, such as \"Release Readiness\", \"Payments Migration\", or \"On-Call Incidents\". Not individual tasks.",
            builtIn: true
        ),
        SummaryTemplate(
            id: "brainstorm",
            name: "Brainstorm / planning",
            icon: "lightbulb",
            instructions: """
            This is a brainstorm or planning session. Preserve the breadth of ideas; do not collapse them into one conclusion. \
            Problem framing: the problem or goal being worked on, constraints, and how success was defined. \
            Ideas: every distinct idea, grouped under "### " theme subheadings, each with who proposed it (when named) and the main argument for or against it. \
            Promising directions: the ideas the group got most excited about or converged on, and why. \
            Open questions: unknowns and assumptions to check. \
            Next experiments: concrete tests, prototypes, or research to run next, with owner.
            """,
            sections: ["Problem framing", "Ideas", "Promising directions", "Open questions", "Next experiments"],
            topicFocus: "the problem spaces and idea themes explored, such as \"Onboarding Friction\", \"Growth Experiments\", or \"Q4 Roadmap\".",
            builtIn: true
        ),
    ]

    static var general: SummaryTemplate { builtIns[0] }

    /// A blank custom template.
    static func blank() -> SummaryTemplate {
        SummaryTemplate(
            id: UUID().uuidString,
            name: "New template",
            icon: "doc.text",
            instructions: "",
            sections: ["Summary", "Key points", "Action items"],
            topicFocus: "",
            builtIn: false
        )
    }

    /// An editable custom copy.
    func duplicate() -> SummaryTemplate {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = "\(name) copy"
        copy.builtIn = false
        return copy
    }

    /// Icons offered in the template editor.
    static let iconChoices = [
        "doc.text", "person.crop.circle.badge.checkmark", "person.2", "person.3", "lightbulb",
        "briefcase", "chart.line.uptrend.xyaxis", "hammer", "wrench.and.screwdriver", "graduationcap",
        "stethoscope", "building.2", "megaphone", "magnifyingglass", "checklist", "star", "flag", "bubble.left.and.bubble.right",
    ]
}

/// Built-in templates plus the user's custom ones at ~/Library/Application Support/GrokNotes/templates.json.
@MainActor
final class TemplateCatalog: ObservableObject {
    @Published private(set) var custom: [SummaryTemplate] = []
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("templates.json")
        if let data = try? Data(contentsOf: url) {
            custom = ((try? JSONDecoder().decode([SummaryTemplate].self, from: data)) ?? []).map { t in
                var t = t
                t.builtIn = false
                return t
            }
        }
    }

    var all: [SummaryTemplate] { SummaryTemplate.builtIns + custom }

    func lookup(_ id: String?) -> SummaryTemplate? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// The template for `id`, else the default from Settings, else General meeting.
    func resolve(_ id: String?) -> SummaryTemplate {
        lookup(id) ?? lookup(Prefs.defaultTemplateID) ?? .general
    }

    func template(for meeting: Meeting) -> SummaryTemplate {
        resolve(meeting.templateID)
    }

    /// Adds or replaces a custom template. Built-ins cannot be changed.
    func save(_ template: SummaryTemplate) {
        guard !SummaryTemplate.builtIns.contains(where: { $0.id == template.id }) else { return }
        var t = template
        t.builtIn = false
        t.name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
        t.sections = t.sections.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if t.name.isEmpty { t.name = "Untitled template" }
        if let index = custom.firstIndex(where: { $0.id == t.id }) {
            custom[index] = t
        } else {
            custom.append(t)
        }
        persist()
    }

    func remove(_ id: String) {
        custom.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(custom).write(to: url, options: .atomic)
    }
}
