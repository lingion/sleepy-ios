#if DEBUG && !WIDGET_EXT && !WATCH_APP
import UIKit
import CryptoKit

struct ConsoleUINode {
    var tag: String?
    var text: String?
    var className: String
    var role: String
    var clickable: Bool
    var reachable: Bool
    var bounds: CGRect
    var object: NSObject?

    func json(center: Bool = false) -> [String: Any] {
        var result: [String: Any] = ["tag": tag as Any? ?? NSNull(), "text": text as Any? ?? NSNull(),
            "className": className, "role": role, "clickable": clickable, "reachable": reachable,
            "bounds": ["l": bounds.minX, "t": bounds.minY, "r": bounds.maxX, "b": bounds.maxY]]
        if center { result["center"] = ["x": bounds.midX, "y": bounds.midY] }
        return result
    }
}

struct ConsoleUISelector {
    private let strings: [String: String]
    private let clickable: Bool?
    private let index: Int?

    init(_ o: [String: Any]) throws {
        var values: [String: String] = [:]
        for key in ["testTag", "text", "textContains", "className", "role"] where o[key] != nil {
            let value = try ConsoleJSON.string(o, key)
            if !value.isEmpty { values[key] = value }
        }
        strings = values
        clickable = o["clickable"] == nil ? nil : try ConsoleJSON.bool(o, "clickable")
        index = o["index"] == nil ? nil : try ConsoleJSON.integer(o, "index")
        guard !values.isEmpty || clickable != nil else { throw ConsoleFailure("selector needs at least one criterion") }
    }

    func select(_ nodes: [ConsoleUINode]) -> [ConsoleUINode] {
        let hits = nodes.filter { node in
            (strings["testTag"].map { node.tag == $0 } ?? true) &&
            (strings["text"].map { node.text == $0 } ?? true) &&
            (strings["textContains"].map { node.text?.contains($0) == true } ?? true) &&
            (strings["className"].map { node.className == $0 } ?? true) &&
            (strings["role"].map { node.role == $0 } ?? true) &&
            (clickable.map { node.clickable == $0 } ?? true)
        }
        guard let index else { return hits }
        return hits.indices.contains(index) ? [hits[index]] : []
    }
}

@MainActor
final class ConsoleUIHandlers {
    private weak var root: AppRootViewModel?
    private let windowProvider: () -> UIWindow?

    init(root: AppRootViewModel?, window: @escaping () -> UIWindow? = {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }) { self.root = root; windowProvider = window }

    func install(on router: ConsoleRouter) {
        router.register("GET", "/v1/ui/tree") { [self] _ in try tree() }
        router.register("POST", "/v1/ui/find") { [self] request in
            let hits = try ConsoleUISelector(request.object()).select(snapshot())
            return ["hits": hits.map { $0.json(center: true) }, "total": hits.count]
        }
        router.register("POST", "/v1/ui/action") { [self] in try action($0.object()) }
        router.register("GET", "/v1/ui/screenshot") { [self] _ in try screenshot() }
    }

    private var activity: String {
        guard let root else { return "UIKit" }
        return "\(root.currentTab)/\(root.overlayScreen?.rawValue ?? "main")/\(root.scheduleViewMode)"
    }

    func snapshot() throws -> [ConsoleUINode] {
        guard let window = windowProvider() else { throw ConsoleFailure(409, "no foreground window") }
        var nodes: [ConsoleUINode] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 80, seen.count < 4000, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if let view = object as? UIView, view.isHidden || view.alpha < 0.01 || view.accessibilityElementsHidden { return }
            let tag = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
            let text = object.accessibilityLabel ?? (object as? UILabel)?.text ?? (object as? UITextField)?.text
            let traits = object.accessibilityTraits
            let control = object as? UIControl
            let button = traits.contains(.button) || object is UIButton
            let input = object is UITextField || object is UITextView
            let scroll = object is UIScrollView
            if object.isAccessibilityElement || tag != nil || text != nil || control != nil || scroll {
                // UIView 与 UIAccessibilityElement 都转换到 key window 的 point 坐标。
                let bounds: CGRect
                if let view = object as? UIView { bounds = view.convert(view.bounds, to: window) }
                else { bounds = window.convert(object.accessibilityFrame, from: window.screen.coordinateSpace) }
                let enabled = !(control?.isEnabled == false) && !traits.contains(.notEnabled)
                nodes.append(ConsoleUINode(tag: tag, text: text, className: String(describing: type(of: object)),
                    role: input ? "TextField" : scroll ? "ScrollView" : button ? "Button" : "Text",
                    clickable: enabled && (button || control != nil),
                    reachable: enabled && !bounds.isEmpty && window.bounds.intersects(bounds), bounds: bounds, object: object))
            }
            // SwiftUI 公开的 accessibility container 优先；对象身份去重避免容器/子视图重复。
            if let elements = object.accessibilityElements {
                for child in elements { if let child = child as? NSObject { visit(child, depth: depth + 1) } }
            } else {
                let count = object.accessibilityElementCount()
                if count > 0 && count != NSNotFound {
                    for i in 0..<min(count, 4000) {
                        if let child = object.accessibilityElement(at: i) as? NSObject { visit(child, depth: depth + 1) }
                    }
                }
            }
            if let view = object as? UIView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        visit(window, depth: 0)
        return nodes
    }

    private func fingerprint(_ nodes: [ConsoleUINode]) -> [String: Any] {
        let text = nodes.compactMap(\.text).joined(separator: "\u{1}")
        let hash = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        return ["activity": activity, "tags": Array(Set(nodes.compactMap(\.tag))).sorted(),
                "focus": nodes.first { ($0.object as? UIResponder)?.isFirstResponder == true }?.tag as Any? ?? NSNull(),
                "textHash": hash]
    }

    func tree() throws -> Any {
        let nodes = try snapshot()
        return ["activity": activity, "nodes": nodes.map { $0.json() },
                "dump": nodes.map { "\($0.className) tag=\($0.tag ?? "") text=\($0.text ?? "")" },
                "fingerprint": fingerprint(nodes), "coordinateUnit": "points"]
    }

    func action(_ o: [String: Any]) throws -> Any {
        let action = try ConsoleJSON.string(o, "action")
        let nodes = try snapshot()
        let before = fingerprint(nodes)
        var hits: [ConsoleUINode] = []
        if let raw = o["selector"] {
            guard let selector = raw as? [String: Any] else { throw ConsoleFailure("selector must be an object") }
            hits = try ConsoleUISelector(selector).select(nodes)
            guard !hits.isEmpty else { throw ConsoleFailure(404, "no node matches selector") }
            guard hits[0].reachable else { throw ConsoleFailure(409, "node is not reachable") }
        }
        switch action {
        case "navigate": try navigate(try ConsoleJSON.string(o, "target"))
        case "back":
            guard let root, root.navigator.pop() else { throw ConsoleFailure(409, "no root overlay to dismiss") }
        case "tap":
            guard let object = hits.first?.object else { throw ConsoleFailure(501, "tap requires selector; coordinate injection unavailable on iOS") }
            if let button = object as? UIButton, button.isEnabled {
                button.sendActions(for: button.allControlEvents.contains(.primaryActionTriggered) ? .primaryActionTriggered : .touchUpInside)
            } else if !object.accessibilityActivate() {
                throw ConsoleFailure(501, "node has no native accessibility activation")
            }
        case "input":
            let text = try ConsoleJSON.string(o, "text")
            let target = hits.first?.object ?? nodes.first { ($0.object as? UIResponder)?.isFirstResponder == true }?.object
            if let field = target as? UITextField, field.isEnabled {
                guard field.becomeFirstResponder() else { throw ConsoleFailure(409, "cannot focus input") }
                field.insertText(text)
            } else if let view = target as? UITextView, view.isEditable {
                guard view.becomeFirstResponder() else { throw ConsoleFailure(409, "cannot focus input") }
                view.insertText(text)
            } else { throw ConsoleFailure(501, "target is not a native editable text input") }
        case "scroll":
            let direction = try ConsoleJSON.string(o, "direction")
            let amount = try ConsoleJSON.integer(o, "amount", default: 400)
            guard (1...10000).contains(amount), ["up", "down", "left", "right"].contains(direction) else {
                throw ConsoleFailure("invalid scroll direction/amount")
            }
            let target = hits.first?.object ?? nodes.first { $0.reachable && $0.object is UIScrollView }?.object
            guard let scroll = target as? UIScrollView, scroll.isScrollEnabled else {
                throw ConsoleFailure(501, "target is not a native scroll view")
            }
            let inset = scroll.adjustedContentInset
            var point = scroll.contentOffset
            if direction == "up" { point.y -= CGFloat(amount) }
            if direction == "down" { point.y += CGFloat(amount) }
            if direction == "left" { point.x -= CGFloat(amount) }
            if direction == "right" { point.x += CGFloat(amount) }
            point.x = max(-inset.left, min(point.x, scroll.contentSize.width - scroll.bounds.width + inset.right))
            point.y = max(-inset.top, min(point.y, scroll.contentSize.height - scroll.bounds.height + inset.bottom))
            scroll.setContentOffset(point, animated: false)
        case "longTap", "doubleTap", "swipe", "drag", "home", "recents", "key":
            throw ConsoleFailure(501, "system gesture/key injection unavailable through public iOS APIs")
        default: throw ConsoleFailure("unknown UI action")
        }
        let after = fingerprint(try snapshot())
        let oldTags = Set(before["tags"] as? [String] ?? []), newTags = Set(after["tags"] as? [String] ?? [])
        return ["matched": hits.count, "settled": false, "diff": [
            "appeared": newTags.subtracting(oldTags).sorted(), "disappeared": oldTags.subtracting(newTags).sorted(),
            "focus": ["before": before["focus"]!, "after": after["focus"]!],
            "textChanged": before["textHash"] as? String != after["textHash"] as? String,
            "activityChanged": before["activity"] as? String != after["activity"] as? String]]
    }

    private func navigate(_ target: String) throws {
        guard let root else { throw ConsoleFailure(409, "root view model unavailable") }
        // 只列无参数且已落地的导航；使用现有丢弃/返回链，不直接清 overlay。
        let tabs: [String: AppRootViewModel.Tab] = ["schedule": .schedule, "today": .today, "manage": .manage, "mine": .mine]
        if let tab = tabs[target] { root.navigator.popToMain(); root.currentTab = tab; return }
        guard root.overlayScreen == nil else { throw ConsoleFailure(409, "dismiss existing overlay before navigating") }
        switch target {
        case "general": root.navigator.openGeneral()
        case "allTables": root.navigator.openAllTables()
        case "courseList": root.navigator.openCourseList()
        case "periodTables": root.navigator.openPeriodTables()
        case "appearance": root.navigator.openAppearance()
        case "about": root.navigator.openAbout()
        case "reminder": root.navigator.openReminder()
        default: throw ConsoleFailure("unsupported navigation target")
        }
    }

    func screenshot() throws -> Any {
        guard let window = windowProvider(), !window.bounds.isEmpty else { throw ConsoleFailure(409, "no foreground window") }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        var drawn = false
        let image = renderer.image { _ in drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        guard drawn, let png = image.pngData() else { throw ConsoleFailure(500, "screenshot failed") }
        return ["format": "png", "bytes": png.count, "image": png.base64EncodedString()]
    }
}
#endif
