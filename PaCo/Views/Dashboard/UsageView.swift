import SwiftUI
import SwiftData
import PaCoShared

struct UsageView: View {
    @Query(sort: \UsageRecord.date, order: .reverse) private var records: [UsageRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Usage").font(.largeTitle).fontWeight(.bold)

            if records.isEmpty {
                ContentUnavailableView(
                    "No Usage Data",
                    systemImage: "chart.bar",
                    description: Text("Usage data will appear once the child device is active.")
                )
            } else {
                List(records) { record in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(record.date.formatted(date: .long, time: .omitted))
                            .font(.headline)
                        Text("Internet: \(formatDuration(record.internetOnDuration))")
                            .font(.subheadline)
                        ForEach(record.appUsage, id: \.bundleIdentifier) { entry in
                            HStack {
                                Text(entry.appName)
                                Spacer()
                                Text(formatDuration(entry.duration))
                                    .foregroundStyle(.secondary)
                                Text("\(entry.launchCount) launches")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
