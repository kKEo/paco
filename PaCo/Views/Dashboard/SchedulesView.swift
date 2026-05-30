import SwiftUI
import SwiftData
import PaCoShared

struct SchedulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var schedules: [Schedule]
    @Query private var profiles: [ChildProfile]
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Schedules")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button("Add Schedule", systemImage: "plus") {
                    showingAddSheet = true
                }
            }

            if schedules.isEmpty {
                ContentUnavailableView(
                    "No Schedules",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Create a schedule to automate internet access.")
                )
            } else {
                List {
                    ForEach(schedules) { schedule in
                        ScheduleRow(schedule: schedule)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(schedules[index])
                        }
                    }
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $showingAddSheet) {
            AddScheduleSheet(profiles: profiles) { schedule in
                modelContext.insert(schedule)
                showingAddSheet = false
            }
        }
    }
}

struct ScheduleRow: View {
    let schedule: Schedule

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(schedule.label)
                        .font(.headline)
                    if !schedule.isActive {
                        Text("Disabled")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text("Off: \(String(format: "%02d:%02d", schedule.offHour, schedule.offMinute)) - On: \(String(format: "%02d:%02d", schedule.onHour, schedule.onMinute))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(schedule.days.map(\.shortName).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if schedule.gracePeriodMinutes > 0 {
                Text("\(schedule.gracePeriodMinutes)min grace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddScheduleSheet: View {
    let profiles: [ChildProfile]
    let onSave: (Schedule) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var offHour = 21
    @State private var offMinute = 0
    @State private var onHour = 7
    @State private var onMinute = 0
    @State private var gracePeriod = 5

    var body: some View {
        VStack(spacing: 20) {
            Text("New Schedule")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Label (e.g., School nights)", text: $label)
                .textFieldStyle(.roundedBorder)

            // Day selector
            HStack(spacing: 8) {
                ForEach(DayOfWeek.allCases) { day in
                    Toggle(day.shortName, isOn: Binding(
                        get: { selectedDays.contains(day) },
                        set: { isOn in
                            if isOn { selectedDays.insert(day) } else { selectedDays.remove(day) }
                        }
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 20) {
                VStack {
                    Text("Internet OFF at").font(.caption)
                    HStack {
                        Picker("Hour", selection: $offHour) {
                            ForEach(0..<24) { Text("\($0)").tag($0) }
                        }.frame(width: 60)
                        Text(":")
                        Picker("Min", selection: $offMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.frame(width: 60)
                    }
                }
                VStack {
                    Text("Internet ON at").font(.caption)
                    HStack {
                        Picker("Hour", selection: $onHour) {
                            ForEach(0..<24) { Text("\($0)").tag($0) }
                        }.frame(width: 60)
                        Text(":")
                        Picker("Min", selection: $onMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }.frame(width: 60)
                    }
                }
            }

            Stepper("Grace period: \(gracePeriod) min", value: $gracePeriod, in: 0...15)

            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                Button("Create") {
                    let schedule = Schedule(
                        label: label,
                        days: Array(selectedDays),
                        offHour: offHour, offMinute: offMinute,
                        onHour: onHour, onMinute: onMinute,
                        gracePeriodMinutes: gracePeriod
                    )
                    onSave(schedule)
                }
                .disabled(label.isEmpty || selectedDays.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}
