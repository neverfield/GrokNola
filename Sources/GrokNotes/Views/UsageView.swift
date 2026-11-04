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

        VStack(alignment: .leading, spacing: GrokSpacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: GrokSpacing.xs) {
                    Text(total.usd)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("xAI API spend · \(period.rawValue.lowercased())")
                        .font(GrokTypography.captionMuted())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $period) {
                    ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 360)
            }

            HStack(spacing: GrokSpacing.md) {
                statCard("Meetings", "\(meetings.count)")
                statCard("Avg / meeting", meetings.isEmpty ? "–" : (meetings.reduce(0) { $0 + $1.cost } / Double(meetings.count)).usd)
                statCard("Audio transcribed", hours(usage.entries.filter { start == nil || $0.date >= start! }.compactMap(\.audioSeconds).reduce(0, +)))
            }

            HStack(alignment: .top, spacing: GrokSpacing.lg) {
                GroupBox {
                    VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                        Text("By feature")
                            .font(GrokTypography.sectionTitle())
                        if kinds.isEmpty {
                            Text("No usage yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(kinds, id: \.kind) { item in
                                VStack(alignment: .leading, spacing: GrokSpacing.xs) {
                                    HStack {
                                        Text(item.kind.label)
                                        Spacer()
                                        Text(item.cost.usd).monospacedDigit()
                                    }
                                    .font(.callout)
                                    ProgressView(value: total > 0 ? item.cost / total : 0)
                                }
                            }
                        }
                    }
                    .padding(GrokSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 320)

                GroupBox {
                    VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                        Text("By meeting")
                            .font(GrokTypography.sectionTitle())
                        if meetings.isEmpty {
                            Text("No meetings in this period.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            List(meetings, id: \.id) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(state.meeting(item.id)?.title ?? item.title).lineLimit(1)
                                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(GrokTypography.captionMuted())
                                            .foregroundStyle(.secondary)
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
                    .padding(GrokSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("Grok requests show the exact cost xAI reports. Transcription is estimated from recorded audio at list prices. Usage from before this page existed is not included.")
                .font(GrokTypography.captionMuted())
                .foregroundStyle(.secondary)
        }
        .padding(GrokSpacing.contentInset)
        .frame(minWidth: 760, minHeight: 520)
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(title).font(GrokTypography.captionMuted()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GrokSpacing.md)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
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
