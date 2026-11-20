import ClassPlannerCore
import SwiftData
import SwiftUI

enum EntryField: Hashable {
    case code
    case name
    case meeting(UUID)
}

struct CourseView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(UndoCenter.self) private var undoCenter
    @Query private var plans: [Plan]
    @Bindable var course: Course
    let isNew: Bool
    @FocusState private var focus: EntryField?
    @State private var suggesting = false
    @State private var typedCode = false
    @State private var offer: CourseSuggestion?
    @State private var deleting = false

    private var showMissing: Bool { !isNew }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    HStack(spacing: 4) {
                        ColorDot(color: $course.color, striped: false)
                        TextField("Course code", text: $course.code)
                            .font(.title.bold())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .code)
                            .submitLabel(.next)
                            .onSubmit { focus = .name }
                            .missingHighlight(showMissing && !course.hasIdentity)
                    }
                    TextField("Name", text: $course.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.done)
                }

                if suggesting, !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { suggestion in
                            Button {
                                pick(suggestion)
                            } label: {
                                HStack(spacing: 10) {
                                    Swatch(color: suggestion.color, striped: false)
                                        .frame(width: 12, height: 12)
                                    Text(suggestion.code)
                                        .font(.headline)
                                    Text(suggestion.name)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                if let offer {
                    Section {
                        Button("Copy ^[\(offer.sectionCount) section](inflect: true) from \(offer.planName)") { copy(offer) }
                    }
                }

                ForEach(course.orderedSections) { section in
                    SectionEditor(section: section, showMissing: showMissing, canDelete: course.sections.count > 1, focus: $focus) {
                        let copy = course.duplicateSection(section)
                        withAnimation { proxy.scrollTo(copy.id, anchor: .top) }
                    } onDelete: {
                        let label = section.label
                        let snapshot = course.removeSection(section)
                        try? context.save()
                        undoCenter.offer("Deleted section \(label)") {
                            course.restore(snapshot)
                            try? context.save()
                        }
                    }
                    .id(section.id)
                }

                Section {
                    Button("Section", systemImage: "plus") {
                        let section = course.addSection()
                        withAnimation { proxy.scrollTo(section.id, anchor: .top) }
                    }
                    Button("Delete course", role: .destructive) {
                        deleting = true
                        router.path.removeLast()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: focus) { _, field in
            switch field {
            case .code?:
                typedCode = false
                suggesting = true
            case nil:
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if focus == nil { suggesting = false }
                }
            default:
                suggesting = false
            }
        }
        .onChange(of: course.code) { _, code in
            if focus == .code { typedCode = true }
            if let offer, offer.code != code.trimmingCharacters(in: .whitespaces) { self.offer = nil }
        }
        .task {
            guard isNew else { return }
            try? await Task.sleep(for: .milliseconds(450))
            focus = .code
        }
        .onDisappear(perform: leave)
    }

    private var suggestions: [CourseSuggestion] {
        course.suggestions(from: plans, matching: typedCode ? course.code : "")
    }

    private func pick(_ suggestion: CourseSuggestion) {
        course.adopt(suggestion)
        offer = suggestion.sectionCount > 0 ? suggestion : nil
        suggesting = false
        focus = nil
    }

    private func copy(_ suggestion: CourseSuggestion) {
        let before = course.sectionSnapshots
        course.copySections(from: suggestion.source)
        offer = nil
        try? context.save()
        undoCenter.offer("Copied ^[\(suggestion.sectionCount) section](inflect: true)") {
            course.replaceSections(with: before)
            try? context.save()
        }
    }

    private func leave() {
        guard let plan = course.plan, deleting || course.isBlank else { return }
        let title = course.title
        let snapshot = plan.removeCourse(course)
        try? context.save()
        guard deleting else { return }
        undoCenter.offer("Deleted \(title)") {
            plan.restore(snapshot)
            try? context.save()
        }
    }
}

struct SectionEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(UndoCenter.self) private var undoCenter
    @Bindable var section: CourseSection
    let showMissing: Bool
    let canDelete: Bool
    var focus: FocusState<EntryField?>.Binding
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Section {
            HStack {
                Text("Section")
                    .font(.headline)
                TextField("01", text: $section.label)
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: 64)
                    .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 8))
                    .accessibilityLabel("Section number")
                Spacer()
                Menu {
                    Button("Duplicate section", systemImage: "plus.square.on.square", action: onDuplicate)
                    if canDelete {
                        Button("Delete section", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Section \(section.label) options")
            }

            ForEach(section.orderedMeetings) { meeting in
                WeeklyTimeEditor(fields: meeting, showMissing: showMissing, removeLabel: meeting.label.isEmpty ? "Remove meeting" : "Remove \(meeting.label)", canRemove: section.meetings.count > 1) {
                    let label = meeting.label
                    let snapshot = section.removeMeeting(meeting)
                    try? context.save()
                    undoCenter.offer(label.isEmpty ? "Removed meeting" : "Removed \(label)") {
                        section.restore(snapshot)
                        try? context.save()
                    }
                } header: {
                    TextField("Meeting", text: Bindable(meeting).label)
                        .font(.headline)
                        .focused(focus, equals: .meeting(meeting.id))
                }
            }

            Button("Meeting", systemImage: "plus") {
                let meeting = section.addMeeting()
                focus.wrappedValue = .meeting(meeting.id)
            }
        }
    }
}

struct UnavailableView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Environment(UndoCenter.self) private var undoCenter
    @Bindable var time: UnavailableTime
    let isNew: Bool
    @FocusState private var focus: EntryField?
    @State private var deleting = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 4) {
                    ColorDot(color: $time.color, striped: true)
                    TextField("Work, practice…", text: $time.name)
                        .font(.title.bold())
                        .accessibilityLabel("Name")
                        .focused($focus, equals: .name)
                        .submitLabel(.done)
                }
            }

            Section {
                ForEach(time.orderedSlots) { slot in
                    WeeklyTimeEditor(fields: slot, showMissing: !isNew, removeLabel: "Remove time", canRemove: time.slots.count > 1) {
                        let snapshot = time.removeSlot(slot)
                        try? context.save()
                        undoCenter.offer("Removed time") {
                            time.restore(snapshot)
                            try? context.save()
                        }
                    } header: {
                        EmptyView()
                    }
                }
                Button("Time", systemImage: "plus") { time.addSlot() }
            }

            Section {
                Button("Delete", role: .destructive) {
                    deleting = true
                    router.path.removeLast()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard isNew else { return }
            try? await Task.sleep(for: .milliseconds(450))
            focus = .name
        }
        .onDisappear {
            guard let plan = time.plan, deleting || time.isBlank else { return }
            let title = time.title
            let snapshot = plan.removeUnavailableTime(time)
            try? context.save()
            guard deleting else { return }
            undoCenter.offer("Deleted \(title)") {
                plan.restore(snapshot)
                try? context.save()
            }
        }
    }
}

struct WeeklyTimeEditor<Fields: WeeklyTimeFields & Observable, Header: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var fields: Fields
    let showMissing: Bool
    let removeLabel: String
    let canRemove: Bool
    let onRemove: () -> Void
    @ViewBuilder let header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header()
                Spacer(minLength: 0)
                if canRemove {
                    Button(removeLabel, systemImage: "xmark", action: onRemove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }

            dayToggles
                .missingHighlight(showMissing && fields.weekdays.isEmpty)

            ViewThatFits(in: .horizontal) {
                HStack { timeControls }
                VStack(alignment: .leading) { timeControls }
            }

            if case .failure(.endNotAfterStart) = fields.validation {
                Text("End must be after start")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var timeControls: some View {
        timeControl(\.startMinute, label: "Start", fallback: 9 * 60)
        Text("–")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        timeControl(\.endMinute, label: "End", fallback: min((fields.startMinute ?? 9 * 60) + 50, WeeklyTime.minutesPerDay - 1))
    }

    @ViewBuilder
    private var dayToggles: some View {
        let days = Weekday.week(startingOn: .monday)
        if typeSize.isAccessibilitySize {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(days) { dayButton($0) }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(days) { dayButton($0) }
            }
        }
    }

    private func dayButton(_ day: Weekday) -> some View {
        let isOn = fields.weekdays.includes(day)
        return Button {
            fields.weekdays.toggle(day)
        } label: {
            Text(day.shortName)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Color.accentColor : Color(.secondarySystemFill), in: .rect(cornerRadius: 10))
                .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private func timeControl(_ keyPath: ReferenceWritableKeyPath<Fields, Int?>, label: String, fallback: Int) -> some View {
        if let minute = fields[keyPath: keyPath] {
            DatePicker(label, selection: Binding {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            } set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                fields[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }, displayedComponents: .hourAndMinute)
            .labelsHidden()
        } else {
            Button(label) { fields[keyPath: keyPath] = fallback }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .missingHighlight(showMissing)
        }
    }
}

struct ColorDot: View {
    @Binding var color: PlannerColor
    let striped: Bool
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Swatch(color: color, striped: striped)
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color: \(color.name)")
        .sheet(isPresented: $choosing) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(PlannerColor.allCases) { option in
                    Button {
                        color = option
                        choosing = false
                    } label: {
                        Circle()
                            .fill(option.swatch)
                            .frame(width: 52, height: 52)
                            .overlay {
                                if option == color {
                                    Image(systemName: "checkmark")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(option == color ? .isSelected : [])
                }
            }
            .padding(24)
            .presentationDetents([.height(220)])
        }
    }
}

extension View {
    func missingHighlight(_ active: Bool) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .padding(-3)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(false)
        }
        .accessibilityHint(active ? Text("Missing") : Text(""))
    }
}
