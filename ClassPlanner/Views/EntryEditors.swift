import ClassPlannerCore
import SwiftData
import SwiftUI

struct CourseView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Bindable var course: Course
    @State private var deleting = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 4) {
                    ColorDot(color: $course.color)
                    TextField("Course code", text: $course.code)
                        .font(.title.bold())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                TextField("Name", text: $course.name)
            }

            ForEach(course.orderedSections) { section in
                SectionEditor(section: section, canDelete: course.sections.count > 1) {
                    course.duplicateSection(section)
                } onDelete: {
                    course.sections.removeAll { $0.id == section.id }
                    context.delete(section)
                }
            }

            Section {
                Button("Section", systemImage: "plus") { course.addSection() }
                Button("Delete course", role: .destructive) {
                    deleting = true
                    router.path.removeLast()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            guard deleting || course.isBlank, let plan = course.plan else { return }
            plan.courses.removeAll { $0.id == course.id }
            context.delete(course)
        }
    }
}

struct SectionEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var section: CourseSection
    let canDelete: Bool
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
                WeeklyTimeEditor(fields: meeting, canRemove: section.meetings.count > 1) {
                    section.meetings.removeAll { $0.id == meeting.id }
                    context.delete(meeting)
                } header: {
                    TextField("Meeting", text: Bindable(meeting).label)
                        .font(.headline)
                }
            }

            Button("Meeting", systemImage: "plus") { section.addMeeting() }
        }
    }
}

struct UnavailableView: View {
    @Environment(\.modelContext) private var context
    @Environment(Router.self) private var router
    @Bindable var time: UnavailableTime
    @State private var deleting = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 4) {
                    ColorDot(color: $time.color)
                    TextField("Work, practice…", text: $time.name)
                        .font(.title.bold())
                }
            }

            Section {
                ForEach(time.orderedSlots) { slot in
                    WeeklyTimeEditor(fields: slot, canRemove: time.slots.count > 1) {
                        time.slots.removeAll { $0.id == slot.id }
                        context.delete(slot)
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
        .onDisappear {
            guard deleting || time.isBlank, let plan = time.plan else { return }
            plan.unavailableTimes.removeAll { $0.id == time.id }
            context.delete(time)
        }
    }
}

struct WeeklyTimeEditor<Fields: WeeklyTimeFields & Observable, Header: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var fields: Fields
    let canRemove: Bool
    let onRemove: () -> Void
    @ViewBuilder let header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                header()
                Spacer(minLength: 0)
                if canRemove {
                    Button("Remove", systemImage: "xmark", action: onRemove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
            }

            dayToggles

            HStack {
                timeControl(\.startMinute, placeholder: "Start", fallback: 9 * 60)
                Text("–")
                    .foregroundStyle(.secondary)
                timeControl(\.endMinute, placeholder: "End", fallback: min((fields.startMinute ?? 9 * 60) + 50, WeeklyTime.minutesPerDay - 1))
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
    private func timeControl(_ keyPath: ReferenceWritableKeyPath<Fields, Int?>, placeholder: String, fallback: Int) -> some View {
        if let minute = fields[keyPath: keyPath] {
            DatePicker(placeholder, selection: Binding {
                Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            } set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                fields[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }, displayedComponents: .hourAndMinute)
            .labelsHidden()
        } else {
            Button(placeholder) { fields[keyPath: keyPath] = fallback }
                .buttonStyle(.bordered)
        }
    }
}

struct ColorDot: View {
    @Binding var color: PlannerColor
    @State private var choosing = false

    var body: some View {
        Button {
            choosing = true
        } label: {
            Circle()
                .fill(color.swatch)
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
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
