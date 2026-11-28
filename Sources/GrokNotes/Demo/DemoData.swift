#if GROKNOLA_DEMO
import Foundation

/// The made-up library behind the README screenshots. Every person, company, and call here is fictional.
enum DemoData {
    static let myName = "Alex"
    static let heroID = UUID(uuidString: "6F1C2A4E-1B7D-4C8E-9A51-3D2F0B6E7C10")!
    static let syncID = UUID(uuidString: "2B8E5D17-4A3C-4F21-8E6B-91C0D7A3F452")!
    static let healthID = UUID(uuidString: "9D47A0C3-6E15-4B82-A3F9-58E2C1B0D764")!
    /// Seconds into the kickoff where the transcript scene opens: the start of the Timeline chapter.
    static let transcriptFocus = 170.0

    // MARK: Meetings

    static func meetings(now: Date) -> [Meeting] {
        [kickoff(now: now), productSync(now: now), oneOnOne(now: now), health(now: now), roadmap(now: now), escalation(now: now)]
    }

    private static func line(_ who: String, _ at: String, _ length: Double, _ text: String) -> Utterance {
        let parts = at.split(separator: ":").compactMap { Double($0) }
        let start = parts[0] * 60 + parts[1]
        return Utterance(source: who == Meeting.meKey ? .mic : .system, speakerKey: who, start: start, end: start + length, text: text)
    }

    private static func day(_ offset: Int, _ hour: Int, _ minute: Int = 0, from now: Date) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    private static func kickoff(now: Date) -> Meeting {
        let ten = day(0, 10, from: now)
        let start = now.timeIntervalSince(ten) > 3600 ? ten : now.addingTimeInterval(-1800)
        let me = Meeting.meKey
        let sam = "r0"
        let taylor = "r1"
        var m = Meeting(id: heroID, title: "Example Co onboarding kickoff", autoTitle: false, startedAt: start, endedAt: start.addingTimeInterval(1000))
        m.appName = "Zoom"
        m.attendees = ["Sam", "Taylor"]
        m.attendeeEmails = ["sam@exampleco.example", "taylor@example.com"]
        m.externalDomains = ["exampleco.example"]
        m.consentConfirmedAt = start
        m.userNotes = """
        go-live date?
        SSO - they use okta
        import from old tool, ~40k records
        sam owns rollout, training for 12 ppl
        """
        m.utterances = [
            line(me, "00:04", 9, "Thanks for making the time, Sam. Taylor is joining from our side to help with the technical setup."),
            line(sam, "00:14", 12, "Happy to be here. I'm Sam, I run operations at Example Co, and I'll own the rollout on our end."),
            line(taylor, "00:28", 8, "And I'm Taylor. I'll be your contact for single sign-on and the data import."),
            line(me, "00:38", 18, "Great. Today I'd like to agree on a go-live date, sort out single sign-on, plan the import, and figure out training."),
            line(sam, "01:00", 20, "That works. The main thing for us is getting the support team off spreadsheets before our busy season in April."),
            line(me, "01:24", 15, "Understood. Let's start with the date and work backwards from there."),
            line(sam, "01:41", 22, "About forty people will use it every day, but only twelve need full training. The rest just need to look things up."),
            line(me, "02:06", 12, "Good to know. That keeps training small. We'll come back to it."),
            line(taylor, "02:22", 15, "Before the date, which identity provider do you use? It changes the setup order."),
            line(sam, "02:40", 8, "Okta. Let's do the timeline first, though."),
            line(me, "02:52", 14, "Sure. What date are you aiming for?"),
            line(sam, "03:12", 18, "We'd like to be live before the end of March, ideally the week of the 17th."),
            line(me, "03:40", 16, "That works if we have the import file two weeks ahead, so we can test it properly."),
            line(sam, "04:05", 10, "I can get it to you by March 3."),
            line(taylor, "04:20", 20, "If the file is on time, we run a test import that week and the final import the Friday before go-live."),
            line(me, "04:48", 14, "So the plan is a test import the week of March 3 and the final import on March 14."),
            line(sam, "05:10", 15, "And if the file slips, we move go-live rather than rush the import."),
            line(me, "05:30", 10, "Agreed. That's the safer call."),
            line(sam, "05:45", 12, "Good. That gives my team enough notice."),
            line(me, "06:05", 10, "Okay, single sign-on. Taylor?"),
            line(taylor, "06:18", 22, "Since you're on Okta, we'll turn on SSO first, so people sign in with their Example Co accounts from day one. It has to be on before training starts."),
            line(sam, "06:45", 8, "Our IT lead will need instructions."),
            line(taylor, "06:55", 12, "I'll send you the Okta setup guide by Friday. It's about twenty minutes of work on your side."),
            line(sam, "07:12", 9, "Perfect. I'll forward it to our IT lead."),
            line(me, "07:25", 18, "Do you need provisioning too, so new hires get accounts automatically?"),
            line(sam, "07:48", 14, "Eventually, yes. Not for launch."),
            line(taylor, "08:05", 15, "Then we'll leave provisioning for a second phase."),
            line(me, "08:30", 12, "Let's talk data. What are we bringing over?"),
            line(sam, "08:51", 25, "About forty thousand records from our current tool. We can export them as a CSV."),
            line(taylor, "09:30", 20, "CSV is fine. The importer handles that size in one pass."),
            line(taylor, "10:02", 18, "The thing to check is custom fields. Send me the list and I'll map them before the test import."),
            line(sam, "10:25", 12, "We have six or seven. I'll include them with the file."),
            line(me, "10:45", 15, "Anything that shouldn't come over?"),
            line(sam, "11:05", 20, "Duplicates, mostly. We cleaned up last year, so it should be minor."),
            line(sam, "11:37", 18, "The open question is archived records. I need to check with compliance whether we have to keep them in the new system."),
            line(me, "12:00", 12, "No problem. Let us know either way and we'll plan for it."),
            line(taylor, "12:15", 10, "If they come over, we'll tag them as archived."),
            line(me, "12:30", 10, "Last topic, training."),
            line(sam, "12:44", 20, "Twelve people need full training, and I'd like them trained before go-live, not after."),
            line(me, "13:10", 16, "We can run two sessions of six, so people can still cover the support queue."),
            line(sam, "13:30", 12, "Two sessions is great. Mornings work best for us."),
            line(me, "13:45", 10, "I'll send times for the week of March 10."),
            line(me, "14:10", 9, "Let me recap so we're aligned."),
            line(me, "14:20", 16, "Go-live is the week of March 17, and it depends on the import file arriving by March 3."),
            line(sam, "14:40", 8, "Yes, that's right."),
            line(me, "15:02", 7, "Training is two morning sessions of six, the week of March 10."),
            line(me, "15:10", 8, "I'll book those sessions and send the invites."),
            line(taylor, "15:25", 12, "And I'll send the Okta guide by Friday."),
            line(sam, "15:40", 15, "I'll send the import file with the custom fields by March 3, and check on archived records."),
            line(me, "16:00", 12, "Perfect. Thanks, both. Talk soon."),
            line(sam, "16:15", 6, "Thanks, bye."),
        ]
        m.speakers = [
            me: SpeakerInfo(name: nil, attribution: .me),
            sam: SpeakerInfo(name: "Sam", attribution: .inferred, confidence: 0.94, evidence: "Introduced themselves at 00:14 and appears on the invite."),
            taylor: SpeakerInfo(name: "Taylor", attribution: .activeSpeaker, confidence: 0.97),
        ]
        m.mode = .named
        m.chapters = [
            Chapter(title: "Kickoff and goals", start: 0, end: 170),
            Chapter(title: "Timeline", start: 170, end: 365),
            Chapter(title: "Single sign-on", start: 365, end: 510),
            Chapter(title: "Data import", start: 510, end: 750),
            Chapter(title: "Training", start: 750, end: 850),
            Chapter(title: "Recap and next steps", start: 850, end: 1000),
        ]
        m.topics = m.chapters?.map(\.title)
        m.tags = ["Onboarding", "Customers"]
        m.templateID = SummaryTemplate.generalID
        m.notesTemplateID = SummaryTemplate.generalID
        m.setGeneratedNotes("""
        # Example Co onboarding kickoff

        ## Summary
        Kickoff to plan Example Co's rollout. The team agreed to go live the week of March 17, provided the import \
        file arrives by March 3. Single sign-on comes first, and training is two sessions before go-live. Whether \
        archived records come over is still open.

        ## Key points by topic
        ### Timeline
        - Example Co wants to go live the week of March 17, before its busy season in April [03:12] [01:00]
        - The date holds only if the import file arrives two weeks ahead [03:40] [04:05]
        - A test import runs the week of March 3 and the final import on March 14 [04:20] [04:48]

        ### Single sign-on
        - Example Co uses Okta, and SSO must be on before training starts [06:18]
        - Automatic provisioning waits for a second phase [07:48] [08:05]

        ### Data import
        - About 40,000 records move from the current tool as a CSV [08:51] [09:30]
        - Six or seven custom fields need mapping before the test import [10:02] [10:25]

        ### Training
        - Sam owns the rollout, and 12 people need full training before go-live [12:44]

        ## Decisions
        - Go-live is the week of March 17 [14:20]
        - Training is two morning sessions of six people, the week of March 10 [15:02]
        - If the file slips, go-live moves rather than rushing the import [05:10]

        ## Action items
        - [ ] Sam: send the import file with the custom fields, by March 3 [04:05] [15:40]
        - [ ] Taylor: send the Okta SSO setup guide, by Friday [06:55]
        - [ ] Alex: book the two training sessions and send invites [15:10]

        ## Open questions
        - Whether archived records need to come over, pending Example Co's compliance team [11:37]
        """)
        m.chat = [
            ChatMessage(role: "user", content: "Draft a short follow-up email to Sam with the dates we agreed."),
            ChatMessage(role: "assistant", content: """
            **Subject:** Example Co rollout: the dates we agreed

            Hi Sam,

            Thanks for today. Here's what we agreed:

            - **Import file:** you'll send it with the custom fields by **March 3** [04:05]
            - **Imports:** a test import that week, then the final import on **March 14** [04:48]
            - **Training:** two morning sessions of six people, the week of **March 10** [15:02]
            - **Go-live:** the week of **March 17** [14:20]

            Taylor will send the Okta setup guide by Friday [06:55]. Let me know what you hear from compliance about archived records.

            Best,
            Alex
            """),
        ]
        return m
    }

    private static func productSync(now: Date) -> Meeting {
        let start = day(-1, 15, from: now)
        var m = Meeting(id: syncID, title: "Weekly product sync", autoTitle: false, startedAt: start, endedAt: start.addingTimeInterval(1860))
        m.appName = "Google Meet"
        m.attendees = ["Taylor", "Riley", "Morgan"]
        m.attendeeEmails = ["taylor@example.com", "riley@example.com", "morgan@example.com"]
        m.utterances = [
            line(Meeting.meKey, "00:05", 12, "Let's start with onboarding. Riley, where are the checklist designs?"),
            line("r0", "00:20", 25, "The checklist mockups are nearly done. I'll share them by Thursday."),
            line("r1", "01:10", 20, "Release notes for 3.2 are ready. I'll publish them today."),
            line("r2", "02:05", 18, "Two customers asked about SSO this week, so it's worth a slot in the roadmap review."),
        ]
        m.speakers = [
            Meeting.meKey: SpeakerInfo(name: nil, attribution: .me),
            "r0": SpeakerInfo(name: "Riley", attribution: .activeSpeaker, confidence: 0.96),
            "r1": SpeakerInfo(name: "Morgan", attribution: .activeSpeaker, confidence: 0.95),
            "r2": SpeakerInfo(name: "Taylor", attribution: .activeSpeaker, confidence: 0.95),
        ]
        m.mode = .named
        m.tags = ["Product"]
        m.setGeneratedNotes("""
        # Weekly product sync

        ## Summary
        Onboarding checklist designs are close, release notes for 3.2 go out today, and SSO requests are growing.

        ## Action items
        - [ ] Riley: share the onboarding checklist mockups, by Thursday [00:20]
        - [x] Morgan: publish the 3.2 release notes [01:10]
        - [ ] Taylor: add SSO to the roadmap review [02:05]
        """)
        return m
    }

    private static func oneOnOne(now: Date) -> Meeting {
        let start = day(-2, 11, 30, from: now)
        var m = Meeting(title: "1:1 with Morgan", autoTitle: false, startedAt: start, endedAt: start.addingTimeInterval(1500))
        m.appName = "Zoom"
        m.attendees = ["Morgan"]
        m.attendeeEmails = ["morgan@example.com"]
        m.utterances = [
            line(Meeting.meKey, "00:04", 10, "How's the release week going?"),
            line("r0", "00:16", 30, "Busy but good. I'd like to own the next customer webinar."),
        ]
        m.speakers = [
            Meeting.meKey: SpeakerInfo(name: nil, attribution: .me),
            "r0": SpeakerInfo(name: "Morgan", attribution: .inferred, confidence: 0.9),
        ]
        m.mode = .named
        m.tags = ["1:1"]
        m.templateID = "one-on-one"
        m.notesTemplateID = "one-on-one"
        m.setGeneratedNotes("""
        # 1:1 with Morgan

        ## Updates
        - Release week is busy but on track [00:16]

        ## Goals & growth
        - Morgan wants to own the next customer webinar [00:16]

        ## Action items
        - [ ] Alex: introduce Morgan to the events team
        """)
        return m
    }

    private static func health(now: Date) -> Meeting {
        let start = day(-4, 14, from: now)
        var m = Meeting(id: healthID, title: "Sample Health pilot review", autoTitle: false, startedAt: start, endedAt: start.addingTimeInterval(2280))
        m.appName = "Microsoft Teams"
        m.attendees = ["Casey", "Taylor"]
        m.attendeeEmails = ["casey@samplehealth.example", "taylor@example.com"]
        m.externalDomains = ["samplehealth.example"]
        m.consentConfirmedAt = start
        m.utterances = [
            line("r0", "00:30", 25, "The pilot team likes it. Before we expand to the other clinics, we need sign-in through Azure AD."),
            line(Meeting.meKey, "01:05", 15, "That's on our list. Taylor can walk your IT team through it."),
            line("r0", "02:10", 20, "Pricing for two hundred seats is the other thing my CFO will ask about."),
        ]
        m.speakers = [
            Meeting.meKey: SpeakerInfo(name: nil, attribution: .me),
            "r0": SpeakerInfo(name: "Casey", attribution: .inferred, confidence: 0.92),
        ]
        m.mode = .named
        m.tags = ["Customers"]
        m.templateID = "customer"
        m.notesTemplateID = "customer"
        m.setGeneratedNotes("""
        # Sample Health pilot review

        ## Context
        - Sample Health's pilot team is happy and wants to expand to more clinics [00:30]

        ## Objections & concerns
        - Sign-in through Azure AD is required before expanding [00:30]
        - Pricing for 200 seats needs CFO approval [02:10]

        ## Next steps
        - [ ] Taylor: walk Sample Health's IT team through Azure AD sign-in [01:05]
        - [ ] Alex: send a 200-seat quote [02:10]
        """)
        return m
    }

    private static func roadmap(now: Date) -> Meeting {
        let start = day(-9, 13, from: now)
        var m = Meeting(title: "Q1 roadmap brainstorm", autoTitle: false, startedAt: start, endedAt: start.addingTimeInterval(2700))
        m.appName = "Zoom"
        m.attendees = ["Riley", "Morgan", "Taylor"]
        m.utterances = [line("r0", "00:10", 20, "Onboarding is where we lose people, so I'd start there.")]
        m.speakers = [
            Meeting.meKey: SpeakerInfo(name: nil, attribution: .me),
            "r0": SpeakerInfo(name: "Riley", attribution: .activeSpeaker, confidence: 0.95),
        ]
        m.mode = .named
        m.tags = ["Planning"]
        m.pinned = true
        m.templateID = "brainstorm"
        m.notesTemplateID = "brainstorm"
        m.setGeneratedNotes("""
        # Q1 roadmap brainstorm

        ## Ideas
        - Guided onboarding checklist [00:10]
        - Single sign-on for Okta and Azure AD
        """)
        return m
    }

    private static func escalation(now: Date) -> Meeting {
        let start = day(-12, 9, 30, from: now)
        var m = Meeting(title: "Support escalation review", autoTitle: false, startedAt: start, endedAt: start.addingTimeInterval(1320))
        m.appName = "Slack"
        m.attendees = ["Morgan"]
        m.utterances = [line("r0", "00:08", 18, "Three escalations this month were import errors from custom fields.")]
        m.speakers = [
            Meeting.meKey: SpeakerInfo(name: nil, attribution: .me),
            "r0": SpeakerInfo(name: "Morgan", attribution: .activeSpeaker, confidence: 0.95),
        ]
        m.mode = .named
        m.tags = ["Support"]
        m.setGeneratedNotes("""
        # Support escalation review

        ## Summary
        Most escalations this month came from custom fields in imports [00:08]

        ## Action items
        - [x] Morgan: add a custom-field check to the import guide
        """)
        return m
    }

    // MARK: Ask across notes

    static func libraryChat(now: Date) -> [ChatMessage] {
        let meetings = Self.meetings(now: now)
        func cite(_ id: UUID) -> String {
            guard let m = meetings.first(where: { $0.id == id }) else { return "" }
            return "[\(m.title), \(m.startedAt.formatted(.dateTime.month(.abbreviated).day()))](\(LibraryAsk.link(for: m)))"
        }
        return [
            ChatMessage(role: "user", content: "What did Example Co commit to, and by when?"),
            ChatMessage(role: "assistant", content: """
            Sam made two commitments in the \(cite(heroID)):

            - **Send the import file** with its custom fields **by March 3**.
            - **Check with compliance** whether archived records need to come over.

            Go-live is planned for **the week of March 17**, and it depends on that file arriving on time. On our side, Taylor owes Sam the Okta setup guide by Friday.
            """),
            ChatMessage(role: "user", content: "Which customers asked about single sign-on recently?"),
            ChatMessage(role: "assistant", content: """
            Two customers:

            - **Example Co** uses Okta and needs SSO on before training starts (\(cite(heroID))).
            - **Sample Health** needs Azure AD sign-in before the pilot expands to more clinics (\(cite(healthID))).

            Taylor also raised the trend in the \(cite(syncID)) and added SSO to the roadmap review.
            """),
        ]
    }

    // MARK: Usage

    static func usage(now: Date) -> [UsageEntry] {
        meetings(now: now).flatMap { m -> [UsageEntry] in
            let minutes = m.duration / 60
            return [
                UsageEntry(date: m.startedAt, meetingID: m.id, kind: .liveTranscription, model: "grok-voice-transcribe-2.0",
                           audioSeconds: m.duration, costUSD: minutes * 0.2 / 60, exact: false),
                UsageEntry(date: m.startedAt, meetingID: m.id, kind: .batchTranscription, model: "grok-voice-transcribe-2.0",
                           audioSeconds: m.duration, costUSD: minutes * 0.1 / 60, exact: false),
                UsageEntry(date: m.startedAt, meetingID: m.id, kind: .notes, model: "grok-4.7", costUSD: 0.031, exact: true),
            ]
        }
    }

    // MARK: Calendar

    static func events(now: Date) -> [CalendarEvent] {
        let me = CalendarAttendee(name: myName, email: "alex@example.com", isSelf: true)
        func person(_ name: String, _ email: String) -> CalendarAttendee { CalendarAttendee(name: name, email: email) }
        let today = Calendar.current.startOfDay(for: now)
        return [
            CalendarEvent(id: "demo-planning", title: "Planning week", start: today,
                          end: today.addingTimeInterval(86400), allDay: true),
            CalendarEvent(id: "demo-design", title: "Design review: onboarding flow",
                          start: now.addingTimeInterval(25 * 60), end: now.addingTimeInterval(55 * 60),
                          attendees: [me, person("Riley", "riley@example.com"), person("Morgan", "morgan@example.com")],
                          conferenceURL: URL(string: "https://zoom.us/j/5550100123")),
            CalendarEvent(id: "demo-health", title: "Sample Health pilot check-in",
                          start: now.addingTimeInterval(80 * 60), end: now.addingTimeInterval(110 * 60),
                          attendees: [me, person("Casey", "casey@samplehealth.example")],
                          conferenceURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            CalendarEvent(id: "demo-retro", title: "Team retro",
                          start: now.addingTimeInterval(130 * 60), end: now.addingTimeInterval(160 * 60),
                          attendees: [me, person("Taylor", "taylor@example.com"), person("Morgan", "morgan@example.com")]),
        ]
    }
}
#endif
