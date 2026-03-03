import SwiftUI
import NotesDomain

// MARK: - Shared View Modifiers

struct DNCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background(.background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .primary.opacity(0.08), radius: 3, y: 1.5)
    }
}

struct DNColumnModifier: ViewModifier {
    var isDropTarget: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isDropTarget ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .shadow(color: .primary.opacity(0.05), radius: 2, y: 1)
    }
}

extension View {
    func dnCard(cornerRadius: CGFloat = 10) -> some View {
        modifier(DNCardModifier(cornerRadius: cornerRadius))
    }

    func dnColumn(isDropTarget: Bool = false) -> some View {
        modifier(DNColumnModifier(isDropTarget: isDropTarget))
    }
}

// MARK: - Due Date Styling

enum DueDateStyle {
    static func color(for date: Date) -> Color {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return .orange
        } else if date < Date() {
            return .red
        } else {
            return .secondary
        }
    }
}

// MARK: - Status Colors

extension TaskStatus {
    var accentColor: Color {
        switch self {
        case .backlog: return .gray
        case .next: return .blue
        case .doing: return .orange
        case .waiting: return .purple
        case .done: return .green
        }
    }
}
