import SwiftUI
import XCTest
@testable import NotesDomain
@testable import NotesUI

@MainActor
final class ThemeTests: XCTestCase {
    // MARK: - DueDateStyle

    func testSmoke_DueDateStyleReturnsOrangeForToday() {
        let color = DueDateStyle.color(for: Date())
        XCTAssertEqual(color, .orange, "Today's date should return orange")
    }

    func testSmoke_DueDateStyleReturnsRedForOverdue() throws {
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let color = DueDateStyle.color(for: yesterday)
        XCTAssertEqual(color, .red, "Overdue date should return red")
    }

    func testDueDateStyleReturnsSecondaryForFuture() throws {
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        let color = DueDateStyle.color(for: tomorrow)
        XCTAssertEqual(color, .secondary, "Future date should return secondary")
    }

    func testDueDateStyleReturnsRedForDistantPast() {
        let distantPast = Date(timeIntervalSince1970: 0)
        let color = DueDateStyle.color(for: distantPast)
        XCTAssertEqual(color, .red, "Distant past should return red")
    }

    // MARK: - TaskStatus.accentColor

    func testSmoke_TaskStatusAccentColors() {
        XCTAssertEqual(TaskStatus.backlog.accentColor, .gray)
        XCTAssertEqual(TaskStatus.next.accentColor, .blue)
        XCTAssertEqual(TaskStatus.doing.accentColor, .orange)
        XCTAssertEqual(TaskStatus.waiting.accentColor, .purple)
        XCTAssertEqual(TaskStatus.done.accentColor, .green)
    }

    func testAllStatusCasesHaveDistinctColors() {
        let colors = TaskStatus.allCases.map(\.accentColor)
        let unique = Set(colors.map { "\($0)" })
        XCTAssertEqual(
            unique.count,
            TaskStatus.allCases.count,
            "Each status should map to a distinct color",
        )
    }

    // MARK: - DNCardModifier

    func testSmoke_DNCardModifierAppliesWithDefaultRadius() {
        let view = Text("Test").dnCard()
        XCTAssertNotNil(view, "dnCard modifier should apply without crashing")
    }

    func testDNCardModifierAppliesWithCustomRadius() {
        let view = Text("Test").dnCard(cornerRadius: 20)
        XCTAssertNotNil(view, "dnCard modifier should accept custom radius")
    }

    // MARK: - DNColumnModifier

    func testDNColumnModifierAppliesNotTargeted() {
        let view = Text("Column").dnColumn(isDropTarget: false)
        XCTAssertNotNil(view, "dnColumn modifier should apply when not targeted")
    }

    func testDNColumnModifierAppliesWhenTargeted() {
        let view = Text("Column").dnColumn(isDropTarget: true)
        XCTAssertNotNil(view, "dnColumn modifier should apply when targeted")
    }

    // MARK: - DNGlassCardModifier

    func testSmoke_DNGlassCardModifierDefaultProperties() {
        let modifier = DNGlassCardModifier()
        XCTAssertEqual(modifier.cornerRadius, 10, "Default corner radius should be 10")
        XCTAssertFalse(modifier.isDropTarget, "Default drop target should be false")
    }

    func testDNGlassCardModifierAppliesWithDefaults() {
        let view = Text("Test").dnGlassCard()
        XCTAssertNotNil(view, "dnGlassCard modifier should apply with defaults")
    }

    func testDNGlassCardModifierKanbanCardParams() {
        // Matches kanban card call site: .dnGlassCard(cornerRadius: 8, isDropTarget: ...)
        let modifier = DNGlassCardModifier(cornerRadius: 8, isDropTarget: true)
        XCTAssertEqual(modifier.cornerRadius, 8)
        XCTAssertTrue(modifier.isDropTarget)

        let view = Text("Card").dnGlassCard(cornerRadius: 8, isDropTarget: true)
        XCTAssertNotNil(view)
    }

    func testDNGlassCardModifierDropTargetFalse() {
        let view = Text("Card").dnGlassCard(cornerRadius: 8, isDropTarget: false)
        XCTAssertNotNil(view, "dnGlassCard should apply when not drop targeted")
    }

    // MARK: - DNGlassOverlayModifier

    func testDNGlassOverlayModifierDefaultGlass() {
        // Default glass parameter — only the shape is passed; Glass type is not referenced here.
        let view = Text("Test").dnGlassOverlay(shape: RoundedRectangle(cornerRadius: 8))
        XCTAssertNotNil(view, "dnGlassOverlay should apply with default glass and rounded rect")
    }

#if canImport(Glass)
    func testDNGlassOverlayModifierErrorBannerParams() {
        // Matches error banner: .dnGlassOverlay(glass: .regular.tint(.red), shape: Capsule())
        let view = Text("Error").dnGlassOverlay(glass: .regular.tint(.red), shape: Capsule())
        XCTAssertNotNil(view, "dnGlassOverlay should apply with red-tinted capsule")
    }

    func testDNGlassOverlayModifierGraphFABParams() {
        // Matches graph FAB: .dnGlassOverlay(glass: .regular.tint(.accentColor), shape: Circle())
        let view = Image(systemName: "play.fill")
            .frame(width: 44, height: 44)
            .dnGlassOverlay(glass: .regular.tint(.accentColor), shape: Circle())
        XCTAssertNotNil(view, "dnGlassOverlay should apply with accent-tinted circle")
    }

    func testDNGlassOverlayModifierClearVariant() {
        let view = Text("Test").dnGlassOverlay(glass: .clear, shape: Capsule())
        XCTAssertNotNil(view, "dnGlassOverlay should accept .clear glass variant")
    }
#endif
}
