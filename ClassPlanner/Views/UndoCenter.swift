import SwiftUI

@MainActor
@Observable
final class UndoCenter {
    struct Notice: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    private(set) var notice: Notice?
    private var dismissal: Task<Void, Never>?

    func offer(_ message: String, undo: @escaping () -> Void) {
        dismissal?.cancel()
        let notice = Notice(message: message, undo: undo)
        withAnimation { self.notice = notice }
        AccessibilityNotification.Announcement("\(message). Undo available.").post()
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, self?.notice?.id == notice.id else { return }
            withAnimation { self?.notice = nil }
        }
    }

    func undo() {
        guard let notice else { return }
        dismissal?.cancel()
        withAnimation { self.notice = nil }
        notice.undo()
    }
}

struct UndoToast: View {
    @Environment(UndoCenter.self) private var undoCenter

    var body: some View {
        if let notice = undoCenter.notice {
            HStack(spacing: 12) {
                Text(notice.message)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Undo") { undoCenter.undo() }
                    .fontWeight(.semibold)
                    .tint(Color(red: 0.5, green: 0.69, blue: 1))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(.white)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: 52)
            .background(Color(white: 0.17), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(notice.id)
        }
    }
}
