import XCTest
import UIKit
@testable import Sleepy

@MainActor
final class NativeTabThemeUpdateTests: XCTestCase {
    private final class TrackingTabBar: UITabBar {
        var assignments = 0
        override var standardAppearance: UITabBarAppearance { didSet { assignments += 1 } }
        override var scrollEdgeAppearance: UITabBarAppearance? { didSet { assignments += 1 } }
    }

    func testRepeatedUpdatesSkipAssignmentsButThemeAndSystemResetsStillApply() {
        let tabBar = TrackingTabBar()
        NativeTabBarTheme.apply(lightScheme, to: tabBar)
        let initialAssignments = tabBar.assignments
        XCTAssertGreaterThan(initialAssignments, 0)
        for _ in 0..<100 { NativeTabBarTheme.apply(lightScheme, to: tabBar) }
        XCTAssertEqual(tabBar.assignments, initialAssignments)
        XCTAssertEqual(tabBar.standardAppearance.selectionIndicatorTintColor, UIColor(lightScheme.secondaryContainer))

        NativeTabBarTheme.apply(darkScheme, to: tabBar)
        XCTAssertGreaterThan(tabBar.assignments, initialAssignments)
        XCTAssertEqual(tabBar.tintColor, UIColor(darkScheme.onSecondaryContainer))
        XCTAssertEqual(tabBar.scrollEdgeAppearance?.selectionIndicatorTintColor, UIColor(darkScheme.secondaryContainer))

        // SwiftUI can replace the native appearance without changing our input
        // theme. Check actual UIKit state rather than remembering the last key.
        let reset = UITabBarAppearance()
        reset.backgroundColor = .magenta
        tabBar.standardAppearance = reset
        tabBar.scrollEdgeAppearance = nil
        NativeTabBarTheme.apply(darkScheme, to: tabBar)
        XCTAssertEqual(tabBar.standardAppearance.backgroundColor, .magenta)
        for appearance in [tabBar.standardAppearance, tabBar.scrollEdgeAppearance!] {
            for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                         appearance.compactInlineLayoutAppearance] {
                XCTAssertEqual(item.selected.iconColor, UIColor(darkScheme.onSecondaryContainer))
                XCTAssertEqual(item.normal.iconColor, UIColor(darkScheme.onSurfaceVariant))
                XCTAssertEqual(item.selected.titleTextAttributes[.foregroundColor] as? UIColor,
                               UIColor(darkScheme.onSecondaryContainer))
            }
        }
    }
}
