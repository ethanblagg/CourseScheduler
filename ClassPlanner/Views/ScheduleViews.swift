import ClassPlannerCore
import SwiftUI

enum CalendarSettings {
    static let showWeekends = "showWeekends"
    static let weekStart = "weekStart"
}

extension Plan {
    @MainActor
    func scheduleOutcome() async -> ScheduleOutcome? {
        guard case .ready(let input) = readiness else { return nil }
        return try? await ScheduleSearch.outcome(for: input)
    }
}

extension ScheduleOutcome {
    var headline: String {
        switch self {
        case .schedules(let results):
            let count = "\(results.totalCount)\(results.isExhaustive ? "" : "+")"
            return results.totalCount == 1 && results.isExhaustive ? "1 schedule fits" : "\(count) schedules fit"
        case .noneFit: return "No schedule fits"
        case .inconclusive: return "Too many to check"
        case .noCourses: return "Schedules"
        }
    }
}

struct SchedulesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case week = "Week"
        case agenda = "Agenda"
        var id: String { rawValue }
    }

    @Bindable var plan: Plan
    @State private var outcome: ScheduleOutcome?
    @State private var mode = Mode.week
    @State private var selected: PlannerEvent?
    @State private var showingOptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(outcome?.headline ?? "Schedules")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                if case .schedules(let results) = outcome, let schedule = results.schedules(by: .fewestDays).first {
                    HStack {
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                        Spacer()
                        Button("Calendar options", systemImage: "ellipsis") { showingOptions = true }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    let events = plan.events(for: schedule)
                    switch mode {
                    case .week: WeekCalendar(events: events) { selected = $0 }
                    case .agenda: AgendaList(events: events) { selected = $0 }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: plan.readiness) { outcome = await plan.scheduleOutcome() }
        .sheet(item: $selected) { EventDetail(plan: plan, event: $0) }
        .sheet(isPresented: $showingOptions) { CalendarOptions() }
    }
}

struct WeekCalendar: View {
    let events: [PlannerEvent]
    var highlights: [TimeOverlap] = []
    let onSelect: (PlannerEvent) -> Void
    @AppStorage(CalendarSettings.showWeekends) private var showWeekends = true
    @AppStorage(CalendarSettings.weekStart) private var weekStart = Weekday.monday
    @ScaledMetric(relativeTo: .caption2) private var hourHeight: CGFloat = 56
    private let timeColumn: CGFloat = 50

    var body: some View {
        let layout = CalendarLayout(events: events, weekStart: weekStart, showWeekends: showWeekends)
        let height = CGFloat(layout.hours.count) * hourHeight
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: timeColumn, height: 1)
                ForEach(layout.days) { day in
                    Text(day.shortName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    ForEach(layout.hours.lowerBound...layout.hours.upperBound, id: \.self) { hour in
                        Text(TimeText.hour(hour))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.secondary)
                            .offset(y: CGFloat(hour - layout.hours.lowerBound) * hourHeight - 7)
                    }
                }
                .padding(.trailing, 6)
                .frame(width: timeColumn, height: height, alignment: .topTrailing)
                .accessibilityHidden(true)

                ForEach(layout.days) { day in
                    DayColumn(day: day, layout: layout, highlights: highlights.filter { $0.days.includes(day) }, hourHeight: hourHeight, onSelect: onSelect)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 12)
            .padding(.trailing, 4)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

private struct DayColumn: View {
    let day: Weekday
    let layout: CalendarLayout
    let highlights: [TimeOverlap]
    let hourHeight: CGFloat
    let onSelect: (PlannerEvent) -> Void

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(layout.hoursFromTop(minute)) * hourHeight
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(0...layout.hours.count, id: \.self) { index in
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(index) * hourHeight)
                }
                ForEach(layout.placements(on: day)) { placement in
                    let width = geometry.size.width / CGFloat(placement.laneCount)
                    let top = y(placement.event.time.startMinute)
                    EventBlock(event: placement.event, day: day) { onSelect(placement.event) }
                        .frame(width: max(width - 2, 1), height: max(y(placement.event.time.endMinute) - top - 1, 1))
                        .offset(x: CGFloat(placement.lane) * width + 1, y: top)
                }
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, band in
                    let top = y(band.startMinute)
                    Stripes(color: .red.opacity(0.35), spacing: 5, width: 2)
                        .background(Color.red.opacity(0.08))
                        .overlay(alignment: .top) { Rectangle().fill(.red).frame(height: 1.5) }
                        .overlay(alignment: .bottom) { Rectangle().fill(.red).frame(height: 1.5) }
                        .frame(width: geometry.size.width, height: y(band.endMinute) - top)
                        .offset(y: top)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Color(.separator)).frame(width: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(day.name)
    }
}

private struct EventBlock: View {
    let event: PlannerEvent
    let day: Weekday
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .vertical) {
                VStack(alignment: .leading, spacing: 1) {
                    title.lineLimit(2)
                    Text(TimeText.range(event.time))
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .opacity(0.85)
                }
                title.lineLimit(2)
                title.lineLimit(1)
                Color.clear.frame(width: 0, height: 0)
            }
            .foregroundStyle(event.isClass ? event.color.swatch : Color.secondary)
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if event.isClass {
                    event.color.swatch.opacity(0.16)
                } else {
                    Stripes(color: event.color.swatch.opacity(0.22), spacing: 7, width: 3)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(event.color.swatch).frame(width: 3)
            }
            .clipShape(.rect(cornerRadius: 5))
            .overlay {
                if event.isConflict {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(.red, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityLabel(event.accessibilityText(on: day))
    }

    private var title: some View {
        Text(event.title)
            .font(.caption2.weight(.bold))
    }
}

struct AgendaList: View {
    let events: [PlannerEvent]
    let onSelect: (PlannerEvent) -> Void
    @AppStorage(CalendarSettings.showWeekends) private var showWeekends = true
    @AppStorage(CalendarSettings.weekStart) private var weekStart = Weekday.monday
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = CalendarLayout(events: events, weekStart: weekStart, showWeekends: showWeekends)
        VStack(alignment: .leading, spacing: 18) {
            ForEach(layout.days) { day in
                let items = events.filter { $0.time.weekdays.includes(day) }.sorted { ($0.time.startMinute, $0.time.endMinute) < ($1.time.startMinute, $1.time.endMinute) }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(day.name)
                            .font(.footnote.weight(.semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                Button { onSelect(item) } label: { row(item) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.accessibilityText(on: day))
                                if item.id != items.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func row(_ event: PlannerEvent) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(TimeText.range(event.time))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: stacked ? nil : 92, alignment: .leading)
            HStack(spacing: 10) {
                Swatch(color: event.color, striped: !event.isClass)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.headline)
                    if event.isClass, !event.meetingDetail.isEmpty {
                        Text(event.meetingDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(.rect)
    }
}

struct EventDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @AppStorage(CalendarSettings.weekStart) private var weekStart = Weekday.monday
    let plan: Plan
    let event: PlannerEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                colorControl
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.title2.bold())
                    if !event.code.isEmpty, !event.name.isEmpty {
                        Text(event.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if event.isClass, !event.meetingDetail.isEmpty {
                Text(event.meetingDetail)
            }
            Text("\(TimeText.days(event.time.weekdays, weekStart: weekStart)) · \(TimeText.range(event.time))")
            if let route {
                Button {
                    dismiss()
                    router.path.append(route)
                } label: {
                    Text("Edit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var colorControl: some View {
        switch event.kind {
        case .course(let id, _, _):
            if let course = plan.courses.first(where: { $0.id == id }) {
                ColorDot(color: Bindable(course).color, striped: false)
            }
        case .unavailable(let id, _):
            if let time = plan.unavailableTimes.first(where: { $0.id == id }) {
                ColorDot(color: Bindable(time).color, striped: true)
            }
        }
    }

    private var route: Route? {
        switch event.kind {
        case .course(let id, _, _): plan.courses.first { $0.id == id }.map { .course($0, isNew: false) }
        case .unavailable(let id, _): plan.unavailableTimes.first { $0.id == id }.map { .unavailable($0, isNew: false) }
        }
    }
}

struct CalendarOptions: View {
    @AppStorage(CalendarSettings.showWeekends) private var showWeekends = true
    @AppStorage(CalendarSettings.weekStart) private var weekStart = Weekday.monday

    var body: some View {
        Form {
            Toggle("Weekends", isOn: $showWeekends)
            LabeledContent("Week starts") {
                Picker("Week starts", selection: $weekStart) {
                    Text("Mon").tag(Weekday.monday)
                    Text("Sun").tag(Weekday.sunday)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
        }
        .presentationDetents([.height(220)])
    }
}
