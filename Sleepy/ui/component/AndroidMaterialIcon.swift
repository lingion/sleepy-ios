// Copyright 2025 The Android Open Source Project
// Licensed under the Apache License, Version 2.0.
// See resources/third_party/Android-Material-Icons-NOTICE.txt.

import SwiftUI
import UIKit

/// The exact 24-unit vectors used by Android 1.0.64, with non-zero fill.
/// Toolbar paths: AndroidX Compose Material Icons 1.7.8 official sources.
struct AndroidMaterialIcon: View {
    enum Name {
        case calendarMonth, chevronLeft, chevronRight, iosShare, undo, redo, add, check
    }

    @Environment(\.layoutDirection) private var layoutDirection
    let name: Name
    var size: CGFloat = 24

    var body: some View {
        AndroidVectorShape(vector: vector)
            .fill()
            .frame(width: size, height: size)
            .scaleEffect(x: mirrorsInRTL && layoutDirection == .rightToLeft ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }

    private var mirrorsInRTL: Bool { name == .undo || name == .redo }

    private var vector: Path {
        switch name {
        case .calendarMonth: return AndroidIconGeometry.calendarMonth
        case .chevronLeft: return AndroidIconGeometry.chevronLeft
        case .chevronRight: return AndroidIconGeometry.chevronRight
        case .iosShare: return AndroidIconGeometry.iosShare
        case .undo: return AndroidIconGeometry.undo
        case .redo: return AndroidIconGeometry.redo
        case .add: return AndroidIconGeometry.add
        case .check: return AndroidIconGeometry.check
        }
    }
}

struct AndroidVectorShape: Shape {
    let vector: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        return vector.applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.midX - 12 * scale, dy: rect.midY - 12 * scale)
    }
}

/// Source: ui/component/NavIconParts.kt in Android 1.0.64.
/// Hole subpaths stay in the same Path as their outer boundary.
enum AndroidIconGeometry {
    static let calendarMonth = Path { path in
        path.move(to: CGPoint(x: 19, y: 4))
        path.addLine(to: CGPoint(x: 18, y: 4))
        path.addLine(to: CGPoint(x: 18, y: 2))
        path.addLine(to: CGPoint(x: 16, y: 2))
        path.addLine(to: CGPoint(x: 16, y: 4))
        path.addLine(to: CGPoint(x: 8, y: 4))
        path.addLine(to: CGPoint(x: 8, y: 2))
        path.addLine(to: CGPoint(x: 6, y: 2))
        path.addLine(to: CGPoint(x: 6, y: 4))
        path.addLine(to: CGPoint(x: 5, y: 4))
        path.addCurve(to: CGPoint(x: 3.01, y: 6), control1: CGPoint(x: 3.89, y: 4), control2: CGPoint(x: 3.01, y: 4.9))
        path.addLine(to: CGPoint(x: 3, y: 20))
        path.addCurve(to: CGPoint(x: 5, y: 22), control1: CGPoint(x: 3, y: 21.1), control2: CGPoint(x: 3.89, y: 22))
        path.addLine(to: CGPoint(x: 19, y: 22))
        path.addCurve(to: CGPoint(x: 21, y: 20), control1: CGPoint(x: 20.1, y: 22), control2: CGPoint(x: 21, y: 21.1))
        path.addLine(to: CGPoint(x: 21, y: 6))
        path.addCurve(to: CGPoint(x: 19, y: 4), control1: CGPoint(x: 21, y: 4.9), control2: CGPoint(x: 20.1, y: 4))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19, y: 20))
        path.addLine(to: CGPoint(x: 5, y: 20))
        path.addLine(to: CGPoint(x: 5, y: 10))
        path.addLine(to: CGPoint(x: 19, y: 10))
        path.addLine(to: CGPoint(x: 19, y: 20))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19, y: 8))
        path.addLine(to: CGPoint(x: 5, y: 8))
        path.addLine(to: CGPoint(x: 5, y: 6))
        path.addLine(to: CGPoint(x: 19, y: 6))
        path.addLine(to: CGPoint(x: 19, y: 8))
        path.closeSubpath()
        path.move(to: CGPoint(x: 9, y: 14))
        path.addLine(to: CGPoint(x: 7, y: 14))
        path.addLine(to: CGPoint(x: 7, y: 12))
        path.addLine(to: CGPoint(x: 9, y: 12))
        path.addLine(to: CGPoint(x: 9, y: 14))
        path.closeSubpath()
        path.move(to: CGPoint(x: 13, y: 14))
        path.addLine(to: CGPoint(x: 11, y: 14))
        path.addLine(to: CGPoint(x: 11, y: 12))
        path.addLine(to: CGPoint(x: 13, y: 12))
        path.addLine(to: CGPoint(x: 13, y: 14))
        path.closeSubpath()
        path.move(to: CGPoint(x: 17, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 12))
        path.addLine(to: CGPoint(x: 17, y: 12))
        path.addLine(to: CGPoint(x: 17, y: 14))
        path.closeSubpath()
        path.move(to: CGPoint(x: 9, y: 18))
        path.addLine(to: CGPoint(x: 7, y: 18))
        path.addLine(to: CGPoint(x: 7, y: 16))
        path.addLine(to: CGPoint(x: 9, y: 16))
        path.addLine(to: CGPoint(x: 9, y: 18))
        path.closeSubpath()
        path.move(to: CGPoint(x: 13, y: 18))
        path.addLine(to: CGPoint(x: 11, y: 18))
        path.addLine(to: CGPoint(x: 11, y: 16))
        path.addLine(to: CGPoint(x: 13, y: 16))
        path.addLine(to: CGPoint(x: 13, y: 18))
        path.closeSubpath()
        path.move(to: CGPoint(x: 17, y: 18))
        path.addLine(to: CGPoint(x: 15, y: 18))
        path.addLine(to: CGPoint(x: 15, y: 16))
        path.addLine(to: CGPoint(x: 17, y: 16))
        path.addLine(to: CGPoint(x: 17, y: 18))
        path.closeSubpath()
    }

    static let chevronLeft = Path { path in
        path.move(to: CGPoint(x: 15.41, y: 7.41))
        path.addLine(to: CGPoint(x: 14, y: 6))
        path.addLine(to: CGPoint(x: 8, y: 12))
        path.addLine(to: CGPoint(x: 14, y: 18))
        path.addLine(to: CGPoint(x: 15.41, y: 16.59))
        path.addLine(to: CGPoint(x: 10.83, y: 12))
        path.addLine(to: CGPoint(x: 15.41, y: 7.41))
        path.closeSubpath()
    }

    static let chevronRight = Path { path in
        path.move(to: CGPoint(x: 10, y: 6))
        path.addLine(to: CGPoint(x: 8.59, y: 7.41))
        path.addLine(to: CGPoint(x: 13.17, y: 12))
        path.addLine(to: CGPoint(x: 8.59, y: 16.59))
        path.addLine(to: CGPoint(x: 10, y: 18))
        path.addLine(to: CGPoint(x: 16, y: 12))
        path.addLine(to: CGPoint(x: 10, y: 6))
        path.closeSubpath()
    }

    static let iosShare = Path { path in
        path.move(to: CGPoint(x: 16, y: 5))
        path.addLine(to: CGPoint(x: 14.58, y: 6.42))
        path.addLine(to: CGPoint(x: 12.99, y: 4.83))
        path.addLine(to: CGPoint(x: 12.99, y: 16))
        path.addLine(to: CGPoint(x: 11.01, y: 16))
        path.addLine(to: CGPoint(x: 11.01, y: 4.83))
        path.addLine(to: CGPoint(x: 9.42, y: 6.42))
        path.addLine(to: CGPoint(x: 8, y: 5))
        path.addLine(to: CGPoint(x: 12, y: 1))
        path.addLine(to: CGPoint(x: 16, y: 5))
        path.closeSubpath()
        path.move(to: CGPoint(x: 20, y: 10))
        path.addLine(to: CGPoint(x: 20, y: 21))
        path.addCurve(to: CGPoint(x: 18, y: 23), control1: CGPoint(x: 20, y: 22.1), control2: CGPoint(x: 19.1, y: 23))
        path.addLine(to: CGPoint(x: 6, y: 23))
        path.addCurve(to: CGPoint(x: 4, y: 21), control1: CGPoint(x: 4.89, y: 23), control2: CGPoint(x: 4, y: 22.1))
        path.addLine(to: CGPoint(x: 4, y: 10))
        path.addCurve(to: CGPoint(x: 6, y: 8), control1: CGPoint(x: 4, y: 8.89), control2: CGPoint(x: 4.89, y: 8))
        path.addLine(to: CGPoint(x: 9, y: 8))
        path.addLine(to: CGPoint(x: 9, y: 10))
        path.addLine(to: CGPoint(x: 6, y: 10))
        path.addLine(to: CGPoint(x: 6, y: 21))
        path.addLine(to: CGPoint(x: 18, y: 21))
        path.addLine(to: CGPoint(x: 18, y: 10))
        path.addLine(to: CGPoint(x: 15, y: 10))
        path.addLine(to: CGPoint(x: 15, y: 8))
        path.addLine(to: CGPoint(x: 18, y: 8))
        path.addCurve(to: CGPoint(x: 20, y: 10), control1: CGPoint(x: 19.1, y: 8), control2: CGPoint(x: 20, y: 8.89))
        path.closeSubpath()
    }

    static let undo = Path { path in
        path.move(to: CGPoint(x: 12.5, y: 8))
        path.addCurve(to: CGPoint(x: 5.6, y: 10.6), control1: CGPoint(x: 9.85, y: 8), control2: CGPoint(x: 7.45, y: 8.99))
        path.addLine(to: CGPoint(x: 2, y: 7))
        path.addLine(to: CGPoint(x: 2, y: 16))
        path.addLine(to: CGPoint(x: 11, y: 16))
        path.addLine(to: CGPoint(x: 7.38, y: 12.38))
        path.addCurve(to: CGPoint(x: 12.5, y: 10.5), control1: CGPoint(x: 8.77, y: 11.22), control2: CGPoint(x: 10.54, y: 10.5))
        path.addCurve(to: CGPoint(x: 20.1, y: 16), control1: CGPoint(x: 16.04, y: 10.5), control2: CGPoint(x: 19.05, y: 12.81))
        path.addLine(to: CGPoint(x: 22.47, y: 15.22))
        path.addCurve(to: CGPoint(x: 12.5, y: 8), control1: CGPoint(x: 21.08, y: 11.03), control2: CGPoint(x: 17.15, y: 8))
        path.closeSubpath()
    }

    static let redo = Path { path in
        path.move(to: CGPoint(x: 18.4, y: 10.6))
        path.addCurve(to: CGPoint(x: 11.5, y: 8), control1: CGPoint(x: 16.55, y: 8.99), control2: CGPoint(x: 14.15, y: 8))
        path.addCurve(to: CGPoint(x: 1.54, y: 15.22), control1: CGPoint(x: 6.85, y: 8), control2: CGPoint(x: 2.92, y: 11.03))
        path.addLine(to: CGPoint(x: 3.9, y: 16))
        path.addCurve(to: CGPoint(x: 11.5, y: 10.5), control1: CGPoint(x: 4.95, y: 12.81), control2: CGPoint(x: 7.95, y: 10.5))
        path.addCurve(to: CGPoint(x: 16.62, y: 12.38), control1: CGPoint(x: 13.45, y: 10.5), control2: CGPoint(x: 15.23, y: 11.22))
        path.addLine(to: CGPoint(x: 13, y: 16))
        path.addLine(to: CGPoint(x: 22, y: 16))
        path.addLine(to: CGPoint(x: 22, y: 7))
        path.addLine(to: CGPoint(x: 18.4, y: 10.6))
        path.closeSubpath()
    }

    static let add = Path { path in
        path.move(to: CGPoint(x: 19, y: 13))
        path.addLine(to: CGPoint(x: 13, y: 13))
        path.addLine(to: CGPoint(x: 13, y: 19))
        path.addLine(to: CGPoint(x: 11, y: 19))
        path.addLine(to: CGPoint(x: 11, y: 13))
        path.addLine(to: CGPoint(x: 5, y: 13))
        path.addLine(to: CGPoint(x: 5, y: 11))
        path.addLine(to: CGPoint(x: 11, y: 11))
        path.addLine(to: CGPoint(x: 11, y: 5))
        path.addLine(to: CGPoint(x: 13, y: 5))
        path.addLine(to: CGPoint(x: 13, y: 11))
        path.addLine(to: CGPoint(x: 19, y: 11))
        path.addLine(to: CGPoint(x: 19, y: 13))
        path.closeSubpath()
    }

    static let check = Path { path in
        path.move(to: CGPoint(x: 9, y: 16.17))
        path.addLine(to: CGPoint(x: 4.83, y: 12))
        path.addLine(to: CGPoint(x: 3.41, y: 13.41))
        path.addLine(to: CGPoint(x: 9, y: 19))
        path.addLine(to: CGPoint(x: 21, y: 7))
        path.addLine(to: CGPoint(x: 19.59, y: 5.59))
        path.addLine(to: CGPoint(x: 9, y: 16.17))
        path.closeSubpath()
    }

    static let calFrameAndHoles = Path { path in
        path.move(to: CGPoint(x: 19, y: 4))
        path.addLine(to: CGPoint(x: 18, y: 4))
        path.addLine(to: CGPoint(x: 18, y: 2))
        path.addLine(to: CGPoint(x: 16, y: 2))
        path.addLine(to: CGPoint(x: 16, y: 4))
        path.addLine(to: CGPoint(x: 8, y: 4))
        path.addLine(to: CGPoint(x: 8, y: 2))
        path.addLine(to: CGPoint(x: 6, y: 2))
        path.addLine(to: CGPoint(x: 6, y: 4))
        path.addLine(to: CGPoint(x: 5, y: 4))
        path.addCurve(to: CGPoint(x: 3.01, y: 6), control1: CGPoint(x: 3.89, y: 4), control2: CGPoint(x: 3.01, y: 4.9))
        path.addLine(to: CGPoint(x: 3, y: 20))
        path.addCurve(to: CGPoint(x: 5, y: 22), control1: CGPoint(x: 3, y: 21.1), control2: CGPoint(x: 3.89, y: 22))
        path.addLine(to: CGPoint(x: 19, y: 22))
        path.addCurve(to: CGPoint(x: 21, y: 20), control1: CGPoint(x: 20.1, y: 22), control2: CGPoint(x: 21, y: 21.1))
        path.addLine(to: CGPoint(x: 21, y: 6))
        path.addCurve(to: CGPoint(x: 19, y: 4), control1: CGPoint(x: 21, y: 4.9), control2: CGPoint(x: 20.1, y: 4))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19, y: 20))
        path.addLine(to: CGPoint(x: 5, y: 20))
        path.addLine(to: CGPoint(x: 5, y: 10))
        path.addLine(to: CGPoint(x: 19, y: 10))
        path.addLine(to: CGPoint(x: 19, y: 20))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19, y: 8))
        path.addLine(to: CGPoint(x: 5, y: 8))
        path.addLine(to: CGPoint(x: 5, y: 6))
        path.addLine(to: CGPoint(x: 19, y: 6))
        path.addLine(to: CGPoint(x: 19, y: 8))
        path.closeSubpath()
    }

    static let calDot1 = Path { path in
        path.move(to: CGPoint(x: 9, y: 14))
        path.addLine(to: CGPoint(x: 7, y: 14))
        path.addLine(to: CGPoint(x: 7, y: 12))
        path.addLine(to: CGPoint(x: 9, y: 12))
        path.addLine(to: CGPoint(x: 9, y: 14))
        path.closeSubpath()
    }

    static let calDot2 = Path { path in
        path.move(to: CGPoint(x: 13, y: 14))
        path.addLine(to: CGPoint(x: 11, y: 14))
        path.addLine(to: CGPoint(x: 11, y: 12))
        path.addLine(to: CGPoint(x: 13, y: 12))
        path.addLine(to: CGPoint(x: 13, y: 14))
        path.closeSubpath()
    }

    static let calDot3 = Path { path in
        path.move(to: CGPoint(x: 17, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 12))
        path.addLine(to: CGPoint(x: 17, y: 12))
        path.addLine(to: CGPoint(x: 17, y: 14))
        path.closeSubpath()
    }

    static let calDot4 = Path { path in
        path.move(to: CGPoint(x: 9, y: 18))
        path.addLine(to: CGPoint(x: 7, y: 18))
        path.addLine(to: CGPoint(x: 7, y: 16))
        path.addLine(to: CGPoint(x: 9, y: 16))
        path.addLine(to: CGPoint(x: 9, y: 18))
        path.closeSubpath()
    }

    static let calDot5 = Path { path in
        path.move(to: CGPoint(x: 13, y: 18))
        path.addLine(to: CGPoint(x: 11, y: 18))
        path.addLine(to: CGPoint(x: 11, y: 16))
        path.addLine(to: CGPoint(x: 13, y: 16))
        path.addLine(to: CGPoint(x: 13, y: 18))
        path.closeSubpath()
    }

    static let calDot6 = Path { path in
        path.move(to: CGPoint(x: 17, y: 18))
        path.addLine(to: CGPoint(x: 15, y: 18))
        path.addLine(to: CGPoint(x: 15, y: 16))
        path.addLine(to: CGPoint(x: 17, y: 16))
        path.addLine(to: CGPoint(x: 17, y: 18))
        path.closeSubpath()
    }

    static let todayFrameAndHoles = Path { path in
        path.move(to: CGPoint(x: 19, y: 3))
        path.addLine(to: CGPoint(x: 18, y: 3))
        path.addLine(to: CGPoint(x: 18, y: 1))
        path.addLine(to: CGPoint(x: 16, y: 1))
        path.addLine(to: CGPoint(x: 16, y: 3))
        path.addLine(to: CGPoint(x: 8, y: 3))
        path.addLine(to: CGPoint(x: 8, y: 1))
        path.addLine(to: CGPoint(x: 6, y: 1))
        path.addLine(to: CGPoint(x: 6, y: 3))
        path.addLine(to: CGPoint(x: 5, y: 3))
        path.addCurve(to: CGPoint(x: 3, y: 5), control1: CGPoint(x: 3.89, y: 3), control2: CGPoint(x: 3, y: 3.9))
        path.addLine(to: CGPoint(x: 3, y: 19))
        path.addCurve(to: CGPoint(x: 5, y: 21), control1: CGPoint(x: 3, y: 20.1), control2: CGPoint(x: 3.89, y: 21))
        path.addLine(to: CGPoint(x: 19, y: 21))
        path.addCurve(to: CGPoint(x: 21, y: 19), control1: CGPoint(x: 20.1, y: 21), control2: CGPoint(x: 21, y: 20.1))
        path.addLine(to: CGPoint(x: 21, y: 5))
        path.addCurve(to: CGPoint(x: 19, y: 3), control1: CGPoint(x: 21, y: 3.9), control2: CGPoint(x: 20.1, y: 3))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19, y: 19))
        path.addLine(to: CGPoint(x: 5, y: 19))
        path.addLine(to: CGPoint(x: 5, y: 9))
        path.addLine(to: CGPoint(x: 19, y: 9))
        path.addLine(to: CGPoint(x: 19, y: 19))
        path.closeSubpath()
        path.move(to: CGPoint(x: 19, y: 7))
        path.addLine(to: CGPoint(x: 5, y: 7))
        path.addLine(to: CGPoint(x: 5, y: 5))
        path.addLine(to: CGPoint(x: 19, y: 5))
        path.addLine(to: CGPoint(x: 19, y: 7))
        path.closeSubpath()
    }

    static let todayCenterSquare = Path { path in
        path.move(to: CGPoint(x: 7, y: 11))
        path.addLine(to: CGPoint(x: 12, y: 11))
        path.addLine(to: CGPoint(x: 12, y: 16))
        path.addLine(to: CGPoint(x: 7, y: 16))
        path.closeSubpath()
    }

    static let personHeadRing = Path { path in
        path.move(to: CGPoint(x: 12, y: 4))
        path.addCurve(to: CGPoint(x: 8, y: 8), control1: CGPoint(x: 9.79, y: 4), control2: CGPoint(x: 8, y: 5.79))
        path.addCurve(to: CGPoint(x: 12, y: 12), control1: CGPoint(x: 8, y: 10.21), control2: CGPoint(x: 9.79, y: 12))
        path.addCurve(to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 14.21, y: 12), control2: CGPoint(x: 16, y: 10.21))
        path.addCurve(to: CGPoint(x: 12, y: 4), control1: CGPoint(x: 16, y: 5.79), control2: CGPoint(x: 14.21, y: 4))
        path.closeSubpath()
        path.move(to: CGPoint(x: 12, y: 6))
        path.addCurve(to: CGPoint(x: 14, y: 8), control1: CGPoint(x: 13.1, y: 6), control2: CGPoint(x: 14, y: 6.9))
        path.addCurve(to: CGPoint(x: 12, y: 10), control1: CGPoint(x: 14, y: 9.1), control2: CGPoint(x: 13.1, y: 10))
        path.addCurve(to: CGPoint(x: 10, y: 8), control1: CGPoint(x: 10.9, y: 10), control2: CGPoint(x: 10, y: 9.1))
        path.addCurve(to: CGPoint(x: 12, y: 6), control1: CGPoint(x: 10, y: 6.9), control2: CGPoint(x: 10.9, y: 6))
        path.closeSubpath()
    }

    static let personBody = Path { path in
        path.move(to: CGPoint(x: 12, y: 14))
        path.addCurve(to: CGPoint(x: 4, y: 18), control1: CGPoint(x: 9.33, y: 14), control2: CGPoint(x: 4, y: 15.34))
        path.addLine(to: CGPoint(x: 4, y: 20))
        path.addLine(to: CGPoint(x: 20, y: 20))
        path.addLine(to: CGPoint(x: 20, y: 18))
        path.addCurve(to: CGPoint(x: 12, y: 14), control1: CGPoint(x: 20, y: 15.34), control2: CGPoint(x: 14.67, y: 14))
        path.closeSubpath()
        path.move(to: CGPoint(x: 12, y: 16))
        path.addCurve(to: CGPoint(x: 18, y: 18), control1: CGPoint(x: 14.7, y: 16), control2: CGPoint(x: 17.8, y: 17.29))
        path.addLine(to: CGPoint(x: 6, y: 18))
        path.addCurve(to: CGPoint(x: 12, y: 16), control1: CGPoint(x: 6.23, y: 17.28), control2: CGPoint(x: 9.31, y: 16))
        path.closeSubpath()
    }

    static let settingsRing = Path { path in
        path.move(to: CGPoint(x: 19.43, y: 12.98))
        path.addCurve(to: CGPoint(x: 19.5, y: 12), control1: CGPoint(x: 19.47, y: 12.66), control2: CGPoint(x: 19.5, y: 12.34))
        path.addCurve(to: CGPoint(x: 19.43, y: 11.02), control1: CGPoint(x: 19.5, y: 11.66), control2: CGPoint(x: 19.47, y: 11.34))
        path.addLine(to: CGPoint(x: 21.54, y: 9.37))
        path.addCurve(to: CGPoint(x: 21.66, y: 8.73), control1: CGPoint(x: 21.73, y: 9.22), control2: CGPoint(x: 21.78, y: 8.95))
        path.addLine(to: CGPoint(x: 19.66, y: 5.27))
        path.addCurve(to: CGPoint(x: 19.22, y: 5.02), control1: CGPoint(x: 19.57, y: 5.11), control2: CGPoint(x: 19.4, y: 5.02))
        path.addCurve(to: CGPoint(x: 19.05, y: 5.05), control1: CGPoint(x: 19.16, y: 5.02), control2: CGPoint(x: 19.1, y: 5.03))
        path.addLine(to: CGPoint(x: 16.56, y: 6.05))
        path.addCurve(to: CGPoint(x: 14.87, y: 5.07), control1: CGPoint(x: 16.04, y: 5.65), control2: CGPoint(x: 15.48, y: 5.32))
        path.addLine(to: CGPoint(x: 14.49, y: 2.42))
        path.addCurve(to: CGPoint(x: 14, y: 2), control1: CGPoint(x: 14.46, y: 2.18), control2: CGPoint(x: 14.25, y: 2))
        path.addLine(to: CGPoint(x: 10, y: 2))
        path.addCurve(to: CGPoint(x: 9.51, y: 2.42), control1: CGPoint(x: 9.75, y: 2), control2: CGPoint(x: 9.54, y: 2.18))
        path.addLine(to: CGPoint(x: 9.13, y: 5.07))
        path.addCurve(to: CGPoint(x: 7.44, y: 6.05), control1: CGPoint(x: 8.52, y: 5.32), control2: CGPoint(x: 7.96, y: 5.66))
        path.addLine(to: CGPoint(x: 4.95, y: 5.05))
        path.addCurve(to: CGPoint(x: 4.77, y: 5.02), control1: CGPoint(x: 4.89, y: 5.03), control2: CGPoint(x: 4.83, y: 5.02))
        path.addCurve(to: CGPoint(x: 4.34, y: 5.27), control1: CGPoint(x: 4.6, y: 5.02), control2: CGPoint(x: 4.43, y: 5.11))
        path.addLine(to: CGPoint(x: 2.34, y: 8.73))
        path.addCurve(to: CGPoint(x: 2.46, y: 9.37), control1: CGPoint(x: 2.21, y: 8.95), control2: CGPoint(x: 2.27, y: 9.22))
        path.addLine(to: CGPoint(x: 4.57, y: 11.02))
        path.addCurve(to: CGPoint(x: 4.5, y: 12), control1: CGPoint(x: 4.53, y: 11.34), control2: CGPoint(x: 4.5, y: 11.67))
        path.addCurve(to: CGPoint(x: 4.57, y: 12.98), control1: CGPoint(x: 4.5, y: 12.33), control2: CGPoint(x: 4.53, y: 12.66))
        path.addLine(to: CGPoint(x: 2.46, y: 14.63))
        path.addCurve(to: CGPoint(x: 2.34, y: 15.27), control1: CGPoint(x: 2.27, y: 14.78), control2: CGPoint(x: 2.22, y: 15.05))
        path.addLine(to: CGPoint(x: 4.34, y: 18.73))
        path.addCurve(to: CGPoint(x: 4.78, y: 18.98), control1: CGPoint(x: 4.43, y: 18.89), control2: CGPoint(x: 4.6, y: 18.98))
        path.addCurve(to: CGPoint(x: 4.95, y: 19.01), control1: CGPoint(x: 4.84, y: 18.98), control2: CGPoint(x: 4.9, y: 18.97))
        path.addLine(to: CGPoint(x: 7.44, y: 18.01))
        path.addCurve(to: CGPoint(x: 9.13, y: 18.99), control1: CGPoint(x: 7.96, y: 18.41), control2: CGPoint(x: 8.52, y: 18.74))
        path.addLine(to: CGPoint(x: 9.51, y: 21.64))
        path.addCurve(to: CGPoint(x: 10, y: 22.06), control1: CGPoint(x: 9.54, y: 21.88), control2: CGPoint(x: 9.75, y: 22.06))
        path.addLine(to: CGPoint(x: 14, y: 22.06))
        path.addCurve(to: CGPoint(x: 14.49, y: 21.64), control1: CGPoint(x: 14.25, y: 22.06), control2: CGPoint(x: 14.46, y: 21.88))
        path.addLine(to: CGPoint(x: 14.87, y: 18.99))
        path.addCurve(to: CGPoint(x: 16.56, y: 18.01), control1: CGPoint(x: 15.48, y: 18.74), control2: CGPoint(x: 16.04, y: 18.4))
        path.addLine(to: CGPoint(x: 19.05, y: 19.01))
        path.addCurve(to: CGPoint(x: 19.23, y: 19.04), control1: CGPoint(x: 19.11, y: 19.03), control2: CGPoint(x: 19.17, y: 19.04))
        path.addCurve(to: CGPoint(x: 19.66, y: 18.79), control1: CGPoint(x: 19.4, y: 19.04), control2: CGPoint(x: 19.57, y: 18.95))
        path.addLine(to: CGPoint(x: 21.66, y: 15.33))
        path.addCurve(to: CGPoint(x: 21.54, y: 14.69), control1: CGPoint(x: 21.78, y: 15.11), control2: CGPoint(x: 21.73, y: 14.84))
        path.addLine(to: CGPoint(x: 19.43, y: 13.04))
        path.closeSubpath()
        path.move(to: CGPoint(x: 17.45, y: 11.27))
        path.addCurve(to: CGPoint(x: 17.5, y: 12), control1: CGPoint(x: 17.49, y: 11.58), control2: CGPoint(x: 17.5, y: 11.79))
        path.addCurve(to: CGPoint(x: 17.45, y: 12.73), control1: CGPoint(x: 17.5, y: 12.21), control2: CGPoint(x: 17.48, y: 12.43))
        path.addLine(to: CGPoint(x: 17.31, y: 13.86))
        path.addLine(to: CGPoint(x: 18.2, y: 14.56))
        path.addLine(to: CGPoint(x: 19.28, y: 15.4))
        path.addLine(to: CGPoint(x: 18.58, y: 16.61))
        path.addLine(to: CGPoint(x: 17.31, y: 16.1))
        path.addLine(to: CGPoint(x: 16.27, y: 15.68))
        path.addLine(to: CGPoint(x: 15.37, y: 16.36))
        path.addCurve(to: CGPoint(x: 14.12, y: 17.09), control1: CGPoint(x: 14.94, y: 16.68), control2: CGPoint(x: 14.53, y: 16.92))
        path.addLine(to: CGPoint(x: 13.06, y: 17.52))
        path.addLine(to: CGPoint(x: 12.9, y: 18.65))
        path.addLine(to: CGPoint(x: 12.7, y: 20))
        path.addLine(to: CGPoint(x: 11.3, y: 20))
        path.addLine(to: CGPoint(x: 11.11, y: 18.65))
        path.addLine(to: CGPoint(x: 10.95, y: 17.52))
        path.addLine(to: CGPoint(x: 9.89, y: 17.09))
        path.addCurve(to: CGPoint(x: 8.66, y: 16.38), control1: CGPoint(x: 9.46, y: 16.91), control2: CGPoint(x: 9.06, y: 16.68))
        path.addLine(to: CGPoint(x: 7.75, y: 15.68))
        path.addLine(to: CGPoint(x: 6.69, y: 16.11))
        path.addLine(to: CGPoint(x: 5.42, y: 16.62))
        path.addLine(to: CGPoint(x: 4.72, y: 15.41))
        path.addLine(to: CGPoint(x: 5.8, y: 14.57))
        path.addLine(to: CGPoint(x: 6.69, y: 13.87))
        path.addLine(to: CGPoint(x: 6.55, y: 12.74))
        path.addCurve(to: CGPoint(x: 6.5, y: 12), control1: CGPoint(x: 6.52, y: 12.43), control2: CGPoint(x: 6.5, y: 12.2))
        path.addCurve(to: CGPoint(x: 6.55, y: 11.27), control1: CGPoint(x: 6.5, y: 11.8), control2: CGPoint(x: 6.52, y: 11.57))
        path.addLine(to: CGPoint(x: 6.69, y: 10.14))
        path.addLine(to: CGPoint(x: 5.8, y: 9.44))
        path.addLine(to: CGPoint(x: 4.72, y: 8.6))
        path.addLine(to: CGPoint(x: 5.42, y: 7.39))
        path.addLine(to: CGPoint(x: 6.69, y: 7.9))
        path.addLine(to: CGPoint(x: 7.73, y: 8.32))
        path.addLine(to: CGPoint(x: 8.63, y: 7.64))
        path.addCurve(to: CGPoint(x: 9.88, y: 6.91), control1: CGPoint(x: 9.06, y: 7.32), control2: CGPoint(x: 9.47, y: 7.08))
        path.addLine(to: CGPoint(x: 10.94, y: 6.48))
        path.addLine(to: CGPoint(x: 11.1, y: 5.35))
        path.addLine(to: CGPoint(x: 11.3, y: 4))
        path.addLine(to: CGPoint(x: 12.69, y: 4))
        path.addLine(to: CGPoint(x: 12.88, y: 5.35))
        path.addLine(to: CGPoint(x: 13.04, y: 6.48))
        path.addLine(to: CGPoint(x: 14.1, y: 6.91))
        path.addCurve(to: CGPoint(x: 15.33, y: 7.62), control1: CGPoint(x: 14.53, y: 7.09), control2: CGPoint(x: 14.93, y: 7.32))
        path.addLine(to: CGPoint(x: 16.24, y: 8.32))
        path.addLine(to: CGPoint(x: 17.3, y: 7.89))
        path.addLine(to: CGPoint(x: 18.57, y: 7.38))
        path.addLine(to: CGPoint(x: 19.27, y: 8.59))
        path.addLine(to: CGPoint(x: 18.2, y: 9.44))
        path.addLine(to: CGPoint(x: 17.31, y: 10.14))
        path.addLine(to: CGPoint(x: 17.45, y: 11.27))
        path.closeSubpath()
    }

    static let settingsCore = Path { path in
        path.move(to: CGPoint(x: 12, y: 8))
        path.addCurve(to: CGPoint(x: 8, y: 12), control1: CGPoint(x: 9.79, y: 8), control2: CGPoint(x: 8, y: 9.79))
        path.addCurve(to: CGPoint(x: 12, y: 16), control1: CGPoint(x: 8, y: 14.21), control2: CGPoint(x: 9.79, y: 16))
        path.addCurve(to: CGPoint(x: 16, y: 12), control1: CGPoint(x: 14.21, y: 16), control2: CGPoint(x: 16, y: 14.21))
        path.addCurve(to: CGPoint(x: 12, y: 8), control1: CGPoint(x: 16, y: 9.79), control2: CGPoint(x: 14.21, y: 8))
        path.closeSubpath()
        path.move(to: CGPoint(x: 12, y: 14))
        path.addCurve(to: CGPoint(x: 10, y: 12), control1: CGPoint(x: 10.9, y: 14), control2: CGPoint(x: 10, y: 13.1))
        path.addCurve(to: CGPoint(x: 12, y: 10), control1: CGPoint(x: 10, y: 10.9), control2: CGPoint(x: 10.9, y: 10))
        path.addCurve(to: CGPoint(x: 14, y: 12), control1: CGPoint(x: 13.1, y: 10), control2: CGPoint(x: 14, y: 10.9))
        path.addCurve(to: CGPoint(x: 12, y: 14), control1: CGPoint(x: 14, y: 13.1), control2: CGPoint(x: 13.1, y: 14))
        path.closeSubpath()
    }

}

/// TabView accepts Image/Text tab items. Render the same source vectors as
/// template images so the system tab bar keeps its native glass and selection.
extension AndroidMaterialIcon {
    private static let navigationImages: [String: UIImage] = {
        let parts: [String: [Path]] = [
            "schedule": [AndroidIconGeometry.calendarMonth],
            "today": [AndroidIconGeometry.todayFrameAndHoles, AndroidIconGeometry.todayCenterSquare],
            "manage": [AndroidIconGeometry.settingsRing, AndroidIconGeometry.settingsCore],
            "mine": [AndroidIconGeometry.personHeadRing, AndroidIconGeometry.personBody]
        ]
        return parts.mapValues { paths in
            UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
                context.cgContext.setFillColor(UIColor.black.cgColor)
                for path in paths {
                    context.cgContext.addPath(path.cgPath)
                    context.cgContext.fillPath(using: .winding)
                }
            }.withRenderingMode(.alwaysTemplate)
        }
    }()

    static func navigationImage(for id: String) -> UIImage {
        navigationImages[id] ?? UIImage()
    }
}
