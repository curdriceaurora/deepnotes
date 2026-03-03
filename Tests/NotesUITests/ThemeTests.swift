import XCTest
import SwiftUI
@testable import NotesDomain
@testable import NotesUI

@MainActor
final class ThemeTests: XCTestCase {

    // MARK: - DueDateStyle

    func testDueDateStyleReturnsOrangeForToday() {
        let color = DueDateStyle.color(for: Date())
        XCTAssertEqual(color, .orange, "Today's date should return orange")
    }

    func testDueDateStyleReturnsRedForOverdue() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let color = DueDateStyle.color(for: yesterday)
        XCTAssertEqual(color, .red, "Overdue date should return red")
    }

    func testDueDateStyleReturnsSecondaryForFuture() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let color = DueDateStyle.color(for: tomorrow)
        XCTAssertEqual(color, .secondary, "Future date should return secondary")
    }

    func testDueDateStyleReturnsRedForDistantPast() {
        let distantPast = Date(timeIntervalSince1970: 0)
        let color = DueDateStyle.color(for: distantPast)
        XCTAssertEqual(color, .red, "Distant past should return red")
    }

    // MARK: - TaskStatus.accentColor

    func testTaskStatusAccentColors() {
        XCTAssertEqual(TaskStatus.backlog.accentColor, .gray)
        XCTAssertEqual(TaskStatus.next.accentColor, .blue)
        XCTAssertEqual(TaskStatus.doing.accentColor, .orange)
        XCTAssertEqual(TaskStatus.waiting.accentColor, .purple)
        XCTAssertEqual(TaskStatus.done.accentColor, .green)
    }

    func testAllStatusCasesHaveDistinctColors() {
        let colors = TaskStatus.allCases.map(\.accentColor)
        let unique = Set(colors.map { "\($0)" })
        XCTAssertEqual(unique.count, TaskStatus.allCases.count,
                       "Each status should map to a distinct color")
    }

    // MARK: - DNCardModifier

    func testDNCardModifierAppliesWithDefaultRadius() {
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
}
