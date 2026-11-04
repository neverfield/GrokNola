import SwiftUI

struct UsageView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var usage: UsageLedger
    @State private var period: Period = .month

    enum Period: String, CaseIterable {
        case today = "Today"
        case week = "Last 7 days"
        case month = "This month"
        case all = "All time"

        var start: Date? {
            let calendar = Calendar.current
            switch self {
            case .today: return calendar.startOfDay(for: Date())
            case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
            case .month: return calendar.dateInterval(of: .month, for: Date())?.start
            case .all: return nil
            }
        }
    }

    var body: some View {
        let start = period.start
        let total = usage.total(since: start)
        let kinds = usage.byKind(since: start)
        let meetings = usage.byMeeting(since: start)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(total.usd).font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("xAI API spend, \(period.rawValue.lowercased())").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
            }

            HStack(spacing: 12) {
                stat("Meetings", "\(meetings.count)")
                stat("Average per meeting", meetings.isEmpty ? "–" : (meetings.reduce(0) { $0 + $1.cost } / Double(meetings.count)).usd)
                stat("Audio transcribed", hours(usage.entries.filter { start == nil || $0.date >= start! }.compactMap(\.audioSeconds).reduce(0, +)))
            }

            HStack(alignment: .top, spacing: 16) {
                GroupBox("By feature") {
                    if kinds.isEmpty {
                        Text("No usage yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(kinds, id: \.kind) { item in
                                HStack {
                                    Text(item.kind.label)
                                    Spacer()
                                    Text(item.cost.usd).monospacedDigit()
                                }
                                ProgressView(value: total > 0 ? item.cost / total : 0)
                            }
                        }
                        .padding(4)
                    }
                }
                .frame(width: 320)

                GroupBox("By meeting") {
                    if meetings.isEmpty {
                        Text("No meetings in this period.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        List(meetings, id: \.id) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(state.meeting(item.id)?.title ?? item.title).lineLimit(1)
                                    Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.cost.usd).monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedID = item.id }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 200)
                    }
                }
            }

            Text("Grok requests (notes, names, snapshots, Ask) show the exact cost xAI reports. Transcription is estimated from recorded audio at xAI list prices: $0.20 per hour streaming, $0.10 per hour for the full-recording pass. Usage from before this page existed is not included.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func hours(_ seconds: Double) -> String {
        seconds < 3600 ? "\(Int(seconds / 60)) min" : String(format: "%.1f hr", seconds / 3600)
    }
}

/// Small cost label for a meeting header.
struct MeetingCostLabel: View {
    @EnvironmentObject private var usage: UsageLedger
    let meetingID: UUID

    var body: some View {
        let cost = usage.total(for: meetingID)
        if cost > 0 {
            Text("· \(cost.usd)").help("xAI API cost for this meeting")
        }
    }
}
