import NotesDomain
import SwiftUI

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
                in: RoundedRectangle(cornerRadius: 14),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isDropTarget ? Color.accentColor : Color.clear,
                        lineWidth: 2,
                    ),
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

    func dnGlassCard(cornerRadius: CGFloat = 10, isDropTarget: Bool = false) -> some View {
        modifier(DNGlassCardModifier(cornerRadius: cornerRadius, isDropTarget: isDropTarget))
    }

#if canImport(Glass)
    func dnGlassOverlay(glass: Glass = .regular, shape: some Shape) -> some View {
        modifier(DNGlassOverlayModifier(glass: glass, shape: shape))
    }
#else
    // Fallback: no Glass parameter since the type is unavailable on this SDK.
    func dnGlassOverlay(shape: some Shape) -> some View {
        modifier(DNGlassOverlayModifier(shape: shape))
    }
#endif
}

// MARK: - Glass Modifiers

#if canImport(Glass)
struct DNGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 10
    var isDropTarget: Bool = false

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isDropTarget ? Color.accentColor : .clear, lineWidth: 2),
            )
    }
}

struct DNGlassOverlayModifier<S: Shape>: ViewModifier {
    var glass: Glass = .regular
    var shape: S

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: shape)
    }
}
#else
// Fallback implementations for SDKs without Liquid Glass support (Xcode < 26).
// Glass effects degrade gracefully: cards use a plain background + shadow,
// overlays use .regularMaterial.
struct DNGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 10
    var isDropTarget: Bool = false

    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .primary.opacity(0.08), radius: 3, y: 1.5)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isDropTarget ? Color.accentColor : .clear, lineWidth: 2),
            )
    }
}

struct DNGlassOverlayModifier<S: Shape>: ViewModifier {
    var shape: S

    func body(content: Content) -> some View {
        content.background(.regularMaterial, in: shape)
    }
}
#endif

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

// MARK: - Priority Display

enum PriorityDisplay {
    static func label(for priority: Int) -> String? {
        switch priority {
        case 0: "Urgent"
        case 1: "High"
        case 2: "Medium"
        case 3: "Low"
        case 4: "Minimal"
        default: nil
        }
    }

    static func color(for priority: Int) -> Color {
        switch priority {
        case 0: .red
        case 1: .orange
        case 2: .yellow
        case 3: .blue
        case 4: .purple
        default: .secondary
        }
    }

    static func shouldDisplay(_ priority: Int) -> Bool {
        (0 ... 4).contains(priority)
    }
}

// MARK: - Hex Color Support

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") { hexSanitized.removeFirst() }
        guard hexSanitized.count == 6 else { return nil }
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
        )
    }
}

// MARK: - Status Colors

extension TaskStatus {
    var accentColor: Color {
        switch self {
        case .backlog: .gray
        case .next: .blue
        case .doing: .orange
        case .waiting: .purple
        case .done: .green
        }
    }
}
