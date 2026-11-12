import Foundation

/// Android v1.0.64 toolbar priorities: exhaust margins, scale side actions,
/// then group week navigation. Both sides reserve the larger action width.
struct ScheduleToolbarGeometry {
    let grouped: Bool
    let sideScale: CGFloat
    let sideGap: CGFloat
    let inset: CGFloat
    let gap: CGFloat
    let fitScale: CGFloat
    let centerWidth: CGFloat
    let startWidth: CGFloat
    let endWidth: CGFloat
    let height: CGFloat

    static func resolve(width: CGFloat, fullCenterWidth: CGFloat, groupedCenterWidth: CGFloat,
                        history: Bool, confirm: Bool,
                        normalStartWidth: CGFloat? = nil, tightStartWidth: CGFloat? = nil,
                        normalEndWidth: CGFloat = 104, tightEndWidth: CGFloat = 96,
                        sideHeight: CGFloat = 48, fullCenterHeight: CGFloat = 48,
                        groupedCenterHeight: CGFloat = 32) -> Self {
        let normalStart = normalStartWidth ?? (48 + (history ? 73 : 0) + (confirm ? 56 : 0))
        let tightStart = tightStartWidth ?? (48 + (history ? 65 : 0) + (confirm ? 48 : 0))
        var inset: CGFloat = 12, gap: CGFloat = 8, sideGap: CGFloat = 8, scale: CGFloat = 1
        func sideWidth(_ normal: CGFloat, _ tight: CGFloat) -> CGFloat {
            (tight + (normal - tight) * sideGap / 8) * scale
        }
        func fits() -> Bool {
            fullCenterWidth + 2 <= max(0, width - 2 * (inset + gap + max(sideWidth(normalStart, tightStart), sideWidth(normalEndWidth, tightEndWidth))))
        }
        if !fits() {
            for (edge, between, internalGap): (CGFloat, CGFloat, CGFloat) in [(8, 4, 4), (4, 0, 0), (0, 0, 0)] {
                inset = edge; gap = between; sideGap = internalGap
                if fits() { break }
            }
        }
        if !fits() {
            for value: CGFloat in [0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 2.0 / 3.0] {
                scale = value
                if fits() { break }
            }
        }
        let grouped = !fits()
        let start = sideWidth(normalStart, tightStart), end = sideWidth(normalEndWidth, tightEndWidth)
        let center = grouped ? groupedCenterWidth : fullCenterWidth
        let required = center + 2 * max(start, end) + 2 * gap + 2
        let fit = min(1, max(0, width - 2 * inset) / max(required, 1))
        return Self(grouped: grouped, sideScale: scale, sideGap: sideGap, inset: inset, gap: gap,
                    fitScale: fit, centerWidth: center, startWidth: start, endWidth: end,
                    height: max(sideHeight * scale, grouped ? groupedCenterHeight : fullCenterHeight) * fit)
    }
}
