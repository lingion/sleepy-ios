import SwiftUI
import UIKit

/// Shared drivers keep duplicate icon renderings on the same animation phase.
/// Geometry and scripts follow Android 1.0.64 NavIconParts/NavIconMotion.
@MainActor
private final class NavigationIconMotion: ObservableObject {
    @Published private(set) var pulses: [String: CGFloat] = [:]
    @Published private(set) var spins: [String: CGFloat] = [:]
    private var selected = Set<String>()
    private var initialized = false
    private var activePulses: [String: Pulse] = [:]
    private var gear: GearSpring?
    private var gearPosition = 0.0
    private var gearVelocity = 0.0
    private var gearPressed = false
    private var displayLink: CADisplayLink?
    private var frameTarget: NavigationIconFrameTarget?

    private struct Pulse {
        let start: CFTimeInterval
        let duration: Double
        let linear: Bool
    }

    private struct GearSpring {
        let start: CFTimeInterval
        let origin: Double
        let velocity: Double
        let target: Double
        let stiffness: Double
        let damping: Double
        let press: Bool

        func sample(at time: CFTimeInterval) -> (position: Double, velocity: Double) {
            let t = max(0, time - start)
            let omega = sqrt(stiffness)
            let displacement = origin - target
            if damping == 1 {
                let coefficient = velocity + omega * displacement
                let envelope = exp(-omega * t)
                let position = displacement + coefficient * t
                return (target + envelope * position,
                        envelope * (coefficient - omega * position))
            }
            let decay = damping * omega
            let frequency = omega * sqrt(1 - damping * damping)
            let coefficient = (velocity + decay * displacement) / frequency
            let envelope = exp(-decay * t)
            let position = displacement * cos(frequency * t) + coefficient * sin(frequency * t)
            let derivative = -displacement * frequency * sin(frequency * t)
                + coefficient * frequency * cos(frequency * t)
            return (target + envelope * position, envelope * (derivative - decay * position))
        }
    }

    func synchronize(_ ids: [String], animate: Bool, reduceMotion: Bool) {
        let next = Set(ids)
        let activated = next.subtracting(selected)
        selected = next
        defer { initialized = true }
        guard initialized, animate, !reduceMotion else { return }
        let now = CACurrentMediaTime()
        for id in activated {
            if id == "manage" {
                sampleGear(at: now)
                gear = GearSpring(start: now, origin: gearPosition, velocity: gearVelocity,
                                  target: gearPosition + .pi / 2, stiffness: 200,
                                  damping: 0.75, press: false)
            } else {
                activePulses[id] = Pulse(start: now,
                                         duration: id == "schedule" ? 0.65 : id == "today" ? 0.5 : 0.6,
                                         linear: id == "schedule")
            }
        }
        advance(to: now)
        startFramesIfNeeded()
    }

    func setPressed(_ id: String, _ active: Bool, reduceMotion: Bool) {
        guard id == "manage" else { return }
        let active = active && !reduceMotion
        guard active != gearPressed else { return }
        gearPressed = active
        let now = CACurrentMediaTime()
        sampleGear(at: now)
        if active {
            beginPressStep(at: now)
            startFramesIfNeeded()
        } else if gear?.press == true {
            // Cancellation freezes the actual sampled angle, including an in-flight spring.
            gear = nil
            gearVelocity = 0
            publish(pulses: pulses)
            stopFramesIfIdle()
        }
    }

    func stop() {
        sampleGear(at: CACurrentMediaTime())
        gear = nil
        gearVelocity = 0
        gearPressed = false
        activePulses.removeAll()
        publish(pulses: [:])
        stopFramesIfIdle()
    }

    fileprivate func advance(to time: CFTimeInterval) {
        var values = pulses
        for (id, pulse) in activePulses {
            let progress = min(1, max(0, (time - pulse.start) / pulse.duration))
            values[id] = CGFloat(1 - (pulse.linear ? progress : Self.fastOutSlowIn(progress)))
            if progress == 1 { activePulses.removeValue(forKey: id) }
        }
        sampleGear(at: time)
        if let spring = gear,
           abs(gearPosition - spring.target) < 0.01, abs(gearVelocity) < 0.625 {
            // Compose Float springs use a .01-radian visibility threshold.
            gearPosition = spring.target
            gearVelocity = 0
            gear = nil
            if spring.press && gearPressed { beginPressStep(at: time) }
        }
        publish(pulses: values)
        stopFramesIfIdle()
    }

    private func sampleGear(at time: CFTimeInterval) {
        guard let gear else { return }
        (gearPosition, gearVelocity) = gear.sample(at: time)
    }

    private func beginPressStep(at time: CFTimeInterval) {
        gear = GearSpring(start: time, origin: gearPosition, velocity: gearVelocity,
                          target: gearPosition + .pi / 6, stiffness: 50, damping: 1, press: true)
    }

    private func publish(pulses values: [String: CGFloat]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pulses = values
            spins["manage"] = CGFloat(gearPosition * 180 / .pi)
        }
    }

    private func startFramesIfNeeded() {
        guard displayLink == nil, !activePulses.isEmpty || gear != nil else { return }
        let target = NavigationIconFrameTarget()
        target.motion = self
        let link = CADisplayLink(target: target, selector: #selector(NavigationIconFrameTarget.tick(_:)))
        frameTarget = target
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func stopFramesIfIdle() {
        guard activePulses.isEmpty, gear == nil else { return }
        displayLink?.invalidate()
        displayLink = nil
        frameTarget = nil
    }

    private static func fastOutSlowIn(_ progress: Double) -> Double {
        // Invert cubic x(t) for Android FastOutSlowInEasing(.4, 0, .2, 1).
        guard progress > 0, progress < 1 else { return progress }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<20 {
            let t = (lower + upper) / 2
            let x = 3 * (1 - t) * (1 - t) * t * 0.4 + 3 * (1 - t) * t * t * 0.2 + t * t * t
            if x < progress { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }
}

@MainActor
private final class NavigationIconFrameTarget: NSObject {
    weak var motion: NavigationIconMotion?
    @objc func tick(_ link: CADisplayLink) { motion?.advance(to: link.timestamp) }
}

/// Owns the driver without observing its per-frame publications at the bar level.
@MainActor
private final class NavigationIconBarState: ObservableObject {
    let motion = NavigationIconMotion()
}

private struct AndroidNavigationIconBar: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var state = NavigationIconBarState()
    let selectedIDs: [String]

    func body(content: Content) -> some View {
        content.environmentObject(state.motion)
            .onAppear { state.motion.synchronize(selectedIDs, animate: false, reduceMotion: reduceMotion) }
            .onChange(of: selectedIDs) {
                state.motion.synchronize($0, animate: true, reduceMotion: reduceMotion)
            }
            .onChange(of: reduceMotion) { if $0 { state.motion.stop() } }
            .onChange(of: scenePhase) { if $0 != .active { state.motion.stop() } }
            .onDisappear { state.motion.stop() }
    }
}

struct NavigationIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var motion: NavigationIconMotion
    let id: String
    let selected: Bool
    var size: CGFloat = 24
    var activationID: String? = nil

    private var motionID: String { activationID ?? id }

    var body: some View {
        NavigationIconParts(id: id,
                            pulse: reduceMotion ? 0 : motion.pulses[motionID, default: 0],
                            spin: reduceMotion ? 0 : motion.spins[motionID, default: 0])
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Observe a button's press without replacing its action or native button style.
private struct AndroidNavigationIconPress: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var motion: NavigationIconMotion
    @GestureState private var pressed = false
    let id: String

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressed) { _, active, _ in
                active = true
            })
            .onChange(of: pressed) {
                motion.setPressed(id, $0, reduceMotion: reduceMotion)
            }
            .onDisappear { motion.setPressed(id, false, reduceMotion: reduceMotion) }
    }
}

extension View {
    func androidNavigationIconBar(selectedIDs: [String]) -> some View {
        modifier(AndroidNavigationIconBar(selectedIDs: selectedIDs))
    }

    func androidNavigationIconPress(id: String) -> some View {
        modifier(AndroidNavigationIconPress(id: id))
    }
}

private struct NavigationIconParts: View, Animatable {
    let id: String
    var pulse: CGFloat
    var spin: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pulse, spin) }
        set { pulse = newValue.first; spin = newValue.second }
    }

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 24
            ZStack {
                switch id {
                case "schedule":
                    part(AndroidIconGeometry.calFrameAndHoles)
                    ForEach(0..<6, id: \.self) { index in
                        let state = calendarDot(index)
                        part(calendarDots[index])
                            .scaleEffect(state.scale, anchor: UnitPoint(x: CGFloat(index % 3 * 4 + 8) / 24,
                                                                       y: CGFloat(index / 3 * 4 + 13) / 24))
                            .opacity(state.alpha)
                    }
                case "today":
                    let state = todaySquare
                    part(AndroidIconGeometry.todayFrameAndHoles)
                    part(AndroidIconGeometry.todayCenterSquare)
                        .scaleEffect(state.scale, anchor: UnitPoint(x: 9.5 / 24, y: 13.5 / 24))
                        .opacity(state.alpha)
                case "manage":
                    part(AndroidIconGeometry.settingsRing).rotationEffect(.degrees(Double(spin)))
                    part(AndroidIconGeometry.settingsCore).scaleEffect(1 + 0.12 * sin(pulse * .pi))
                case "mine":
                    let progress = min(1, max(0, 1 - pulse))
                    let wave = pulse > 0 ? pulse * sin(progress * 4 * .pi) : 0
                    part(AndroidIconGeometry.personHeadRing)
                        .rotationEffect(.degrees(Double(18 * wave)), anchor: UnitPoint(x: 0.5, y: 10.0 / 24))
                        .offset(x: 1.2 * wave * unit)
                    part(AndroidIconGeometry.personBody)
                default:
                    EmptyView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func part(_ vector: Path) -> some View {
        AndroidVectorShape(vector: vector).fill()
    }

    private var calendarDots: [Path] {
        [AndroidIconGeometry.calDot1, AndroidIconGeometry.calDot2, AndroidIconGeometry.calDot3,
         AndroidIconGeometry.calDot4, AndroidIconGeometry.calDot5, AndroidIconGeometry.calDot6]
    }

    private func calendarDot(_ index: Int) -> (scale: CGFloat, alpha: Double) {
        guard pulse > 0 else { return (1, 1) }
        let progress = min(1, max(0, 1 - pulse))
        let start = CGFloat(index) * 0.08
        guard progress >= start else { return (0, 0) }
        let u = min(1, max(0, (progress - start) / (1 - start)))
        return (u + 0.25 * sin(u * .pi), Double(min(1, u * 2.5)))
    }

    private var todaySquare: (scale: CGFloat, alpha: Double) {
        guard pulse > 0 else { return (1, 1) }
        let progress = min(1, max(0, 1 - pulse))
        return (progress + 0.35 * sin(progress * .pi), Double(min(1, progress * 2.5)))
    }
}
