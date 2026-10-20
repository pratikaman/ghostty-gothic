import AppKit
import QuartzCore

/// `macos-titlebar-style = gothic`.
///
/// The AppKit titlebar (and with it the native tab bar and traffic lights)
/// is hidden. In its place `GothicChromeView` draws a carved stone header
/// whose top edge is an ogee arch, so the window itself is arch-shaped,
/// plus stained-glass roundels for the window buttons and lancet-arch tabs.
/// Every new window or tab opens behind a pair of cathedral doors.
class GothicTerminalWindow: TerminalWindow {
    static let tabsDidChange = Notification.Name("GothicTerminalWindowTabsDidChange")

    // No titlebar, so no titlebar accessories.
    override var supportsUpdateAccessory: Bool { false }

    private let chrome = GothicChromeView()
    private var doorsOpened = false

    override func awakeFromNib() {
        super.awakeFromNib()
        applyGothicStyle()

        // Any tab appearing, closing, retitling or changing focus redraws
        // every gothic tab strip. Closing windows leave their tab group a
        // moment later, hence the async reload.
        let center = NotificationCenter.default
        for name in [
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.willCloseNotification,
            Self.tabsDidChange,
        ] {
            center.addObserver(self, selector: #selector(tabsDidChange(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(fullscreenDidExit(_:)), name: .fullscreenDidExit, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var contentView: NSView? {
        didSet { installChrome() }
    }

    override var title: String {
        didSet {
            // Setting the title can bring the native title view back.
            applyGothicStyle()
            NotificationCenter.default.post(name: Self.tabsDidChange, object: self)
        }
    }

    override var tabColor: TerminalTabColor {
        didSet { NotificationCenter.default.post(name: Self.tabsDidChange, object: self) }
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        openDoorsOnce()
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        openDoorsOnce()
    }

    // The whole window is our content; the header handles dragging itself.
    override var contentLayoutRect: CGRect {
        var rect = super.contentLayoutRect
        rect.origin.y = 0
        rect.size.height = frame.height
        return rect
    }

    override func syncAppearance(_ surfaceConfig: Ghostty.SurfaceView.DerivedConfig) {
        super.syncAppearance(surfaceConfig)
        guard isVisible else { return }
        applyGothicStyle()
        appearance = NSAppearance(named: .darkAqua)

        // Outside the arch the window is see-through. Native fullscreen
        // goes grey behind transparent windows, so stay opaque there.
        if !styleMask.contains(.fullScreen) {
            isOpaque = false
            backgroundColor = .clear
        }
        chrome.needsDisplay = true
    }

    // MARK: Style

    private static let gothicStyleMask: NSWindow.StyleMask = [
        .titled, .fullSizeContentView, .resizable, .closable, .miniaturizable,
    ]

    private func applyGothicStyle() {
        // Reapplying during non-native fullscreen breaks it (see the
        // hidden titlebar style, issue #8415).
        if terminalController?.fullscreenStyle?.isFullscreen ?? false { return }

        styleMask = styleMask.contains(.fullScreen)
            ? Self.gothicStyleMask.union(.fullScreen)
            : Self.gothicStyleMask
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        guard let themeFrame = contentView?.superview else { return }
        themeFrame.firstDescendant(withClassName: "NSTitlebarContainerView")?.isHidden = true
        if #available(macOS 27, *) {
            themeFrame.firstDescendant(withClassName: "NSScrollPocket")?.isHidden = true
        }
    }

    private func installChrome() {
        guard let container = contentView as? TerminalViewContainer,
              chrome.superview !== container else { return }
        chrome.frame = container.bounds
        chrome.autoresizingMask = [.width, .height]
        container.addSubview(chrome, positioned: .below, relativeTo: nil)
        container.chromeInsets = GothicChromeView.insets
    }

    @objc private func tabsDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.chrome.reload() }
    }

    @objc private func fullscreenDidExit(_ notification: Notification) {
        guard (notification.object as? FullscreenBase)?.window == self else { return }
        applyGothicStyle()
    }

    // MARK: Doors

    private func openDoorsOnce() {
        guard !doorsOpened else { return }
        doorsOpened = true
        // Wait a turn so the content has its final size.
        DispatchQueue.main.async { [weak self] in self?.openDoors() }
    }

    private func openDoors() {
        guard let container = contentView as? TerminalViewContainer,
              let left = Gothic.image("door-left"),
              let right = Gothic.image("door-right") else { return }
        let insets = GothicChromeView.insets
        let doors = GothicDoorsView(frame: NSRect(
            x: insets.left,
            y: insets.bottom,
            width: container.bounds.width - insets.left - insets.right,
            height: container.bounds.height - insets.top - insets.bottom))
        container.addSubview(doors)
        doors.open(left: left, right: right)
    }
}

// MARK: - Chrome

/// The stone header and frame. Sits behind the terminal, which the
/// container insets by `insets`, so only the header and border show.
final class GothicChromeView: NSView {
    /// Height of the ogee crown above the springing line.
    static let archRise: CGFloat = 26
    /// The strip under the crown holding the roundels and tabs.
    static let bandHeight: CGFloat = 30
    static let border: CGFloat = 6
    static let insets = NSEdgeInsets(
        top: archRise + bandHeight, left: border, bottom: border, right: border)

    private let roundels: [GothicRoundel] = [.init(.close), .init(.minimize), .init(.fullscreen)]
    private let newTab = GothicRoundel(.newTab)
    private var tabs: [GothicTabView] = []

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        (roundels + [newTab]).forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reload()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutHeader()
        needsDisplay = true
    }

    /// Rebuild the tab strip from the window's tab group.
    func reload() {
        guard let window else { return }
        let windows = window.tabGroup?.windows ?? [window]
        tabs.forEach { $0.removeFromSuperview() }
        tabs = windows.count > 1 ? windows.map { GothicTabView(target: $0) } : []
        tabs.forEach(addSubview)
        layoutHeader()
        needsDisplay = true
        roundels.forEach { $0.needsDisplay = true }
    }

    private func layoutHeader() {
        let mid = Self.archRise + Self.bandHeight / 2
        for (i, roundel) in roundels.enumerated() {
            roundel.frame = NSRect(x: 16 + CGFloat(i) * 20, y: mid - 7, width: 14, height: 14)
        }
        newTab.frame = NSRect(x: bounds.width - 30, y: mid - 7, width: 14, height: 14)

        guard !tabs.isEmpty else { return }
        let left: CGFloat = 84
        let available = bounds.width - left - 44
        let width = min(220, available / CGFloat(tabs.count))
        var x = left + (available - width * CGFloat(tabs.count)) / 2
        for tab in tabs {
            tab.frame = NSRect(x: x, y: Self.archRise + 2, width: width - 2, height: Self.bandHeight - 2)
            tab.needsDisplay = true
            x += width
        }
    }

    // MARK: Shape

    private var isFullscreen: Bool { window?.styleMask.contains(.fullScreen) ?? false }

    /// The crown: from the left springing point up through an ogee
    /// (convex shoulder, concave approach) to a sharp apex at the top
    /// centre, and back down the mirror image.
    private func crown(rise: CGFloat) -> NSBezierPath {
        let w = bounds.width
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: rise))
        path.curve(to: NSPoint(x: w / 2, y: 0),
                   controlPoint1: NSPoint(x: 0, y: rise * 0.25),
                   controlPoint2: NSPoint(x: w / 2 - w * 0.08, y: rise * 0.6))
        path.curve(to: NSPoint(x: w, y: rise),
                   controlPoint1: NSPoint(x: w / 2 + w * 0.08, y: rise * 0.6),
                   controlPoint2: NSPoint(x: w, y: rise * 0.25))
        return path
    }

    /// The window silhouette: crown on top, walls, rounded bottom corners.
    private var outline: NSBezierPath {
        let rise = isFullscreen ? 0 : Self.archRise
        let path = crown(rise: rise)
        let r: CGFloat = isFullscreen ? 0 : 16
        let w = bounds.width, h = bounds.height
        path.line(to: NSPoint(x: w, y: h - r))
        path.appendArc(withCenter: NSPoint(x: w - r, y: h - r), radius: r, startAngle: 0, endAngle: 90)
        path.line(to: NSPoint(x: r, y: h))
        path.appendArc(withCenter: NSPoint(x: r, y: h - r), radius: r, startAngle: 90, endAngle: 180)
        path.close()
        return path
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Clicks outside the arch fall through to whatever is behind.
        outline.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let outline = self.outline
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()

        // Dressed stone, darkened towards the nave.
        if let stone = Gothic.image("stone") {
            NSColor(patternImage: stone).setFill()
        } else {
            Gothic.nave.setFill()
        }
        bounds.fill()
        Gothic.nave.withAlphaComponent(0.35).setFill()
        bounds.fill(using: .sourceAtop)

        // Moulding: a bright fillet along the crown and a fainter roll
        // under it, then a fillet around the terminal opening.
        let rise = isFullscreen ? 0 : Self.archRise
        if rise > 0 {
            Gothic.limestone.withAlphaComponent(0.7).setStroke()
            let fillet = crown(rise: rise)
            fillet.lineWidth = 2.5
            fillet.stroke()

            Gothic.limestone.withAlphaComponent(0.25).setStroke()
            let roll = crown(rise: rise)
            roll.transform(using: AffineTransform(translationByX: 0, byY: 5))
            roll.lineWidth = 1
            roll.stroke()
        }
        let insets = Self.insets
        let opening = NSRect(
            x: insets.left, y: insets.top,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom)
        Gothic.limestone.withAlphaComponent(0.35).setStroke()
        let fillet = NSBezierPath(rect: opening.insetBy(dx: -1.5, dy: -1.5))
        fillet.lineWidth = 1
        fillet.stroke()

        NSGraphicsContext.restoreGraphicsState()

        drawTitle(rise: rise)
        window?.invalidateShadow()
    }

    /// The window title, in blackletter, centred under the apex.
    private func drawTitle(rise: CGFloat) {
        guard let window, !window.title.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingMiddle
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowBlurRadius = 3
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Gothic.font(14),
            .foregroundColor: Gothic.limestone.withAlphaComponent(window.isKeyWindow ? 1 : 0.55),
            .paragraphStyle: style,
            .shadow: shadow,
        ]
        let width = bounds.width * 0.5
        // With tabs below, the title lives in the crown; without, it sits
        // in the band where it has more room.
        let y = tabs.isEmpty ? rise + 6 : max(rise - 19, 2)
        NSAttributedString(string: window.title, attributes: attributes)
            .draw(in: NSRect(x: (bounds.width - width) / 2, y: y, width: width, height: 20))
    }
}

// MARK: - Roundels

/// A stained-glass roundel set in a stone ring: the window buttons and
/// the new-tab button.
final class GothicRoundel: NSView {
    enum Kind { case close, minimize, fullscreen, newTab }

    let kind: Kind
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        toolTip = switch kind {
        case .close: "Close"
        case .minimize: "Minimize"
        case .fullscreen: "Enter Full Screen"
        case .newTab: "New Tab"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        switch kind {
        case .close: window.performClose(nil)
        case .minimize: window.miniaturize(nil)
        case .fullscreen: window.toggleFullScreen(nil)
        case .newTab: (window.windowController as? TerminalController)?.newTab(nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let glass: NSColor = switch kind {
        case .close: Gothic.ruby
        case .minimize: Gothic.gilt
        case .fullscreen: Gothic.emerald
        case .newTab: Gothic.cobalt
        }
        let lit = (window?.isKeyWindow ?? false) || kind == .newTab
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))

        // Glass lit from behind: bright centre, dark rim.
        let center = lit ? glass.blended(withFraction: 0.35, of: .white) ?? glass : NSColor(white: 0.32, alpha: 1)
        let rim = lit ? glass.blended(withFraction: 0.55, of: .black) ?? glass : NSColor(white: 0.16, alpha: 1)
        NSGradient(starting: center, ending: rim)?.draw(in: circle, relativeCenterPosition: NSPoint(x: -0.2, y: -0.25))

        Gothic.limestone.withAlphaComponent(0.75).setStroke()
        circle.lineWidth = 1.2
        circle.stroke()

        guard hovering || kind == .newTab else { return }
        let glyph = switch kind {
        case .close: "×"
        case .minimize: "–"
        case .fullscreen: "+"
        case .newTab: "+"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.7),
        ]
        let text = NSAttributedString(string: glyph, attributes: attributes)
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

// MARK: - Tabs

/// One tab: a lancet window. The selected tab glows with stained glass,
/// the others are dark stone.
final class GothicTabView: NSView {
    private weak var target: NSWindow?
    private var hovering = false {
        didSet { needsDisplay = true }
    }

    init(target: NSWindow) {
        self.target = target
        super.init(frame: .zero)
        toolTip = target.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var isSelected: Bool {
        guard let target else { return false }
        return (target.tabGroup?.selectedWindow ?? target) === target
    }

    private var closeRect: NSRect {
        NSRect(x: bounds.width - 20, y: bounds.height / 2 - 4, width: 14, height: 14)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        guard let target else { return }
        if closeRect.contains(convert(event.locationInWindow, from: nil)) {
            target.performClose(nil)
        } else if event.clickCount == 2 {
            (target.windowController as? BaseTerminalController)?.promptTabTitle()
        } else {
            target.tabGroup?.selectedWindow = target
            target.makeKeyAndOrderFront(nil)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        target?.performClose(nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename Tab…", action: #selector(renameTab), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Close Tab", action: #selector(closeTab), keyEquivalent: "").target = self
        return menu
    }

    @objc private func renameTab() {
        (target?.windowController as? BaseTerminalController)?.promptTabTitle()
    }

    @objc private func closeTab() {
        target?.performClose(nil)
    }

    /// A lancet: straight jambs and a pointed head with a slight ogee.
    private var lancet: NSBezierPath {
        let w = bounds.width, h = bounds.height, head: CGFloat = 9
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: h))
        path.line(to: NSPoint(x: 0, y: head))
        path.curve(to: NSPoint(x: w / 2, y: 0),
                   controlPoint1: NSPoint(x: 0, y: 2),
                   controlPoint2: NSPoint(x: w / 2 - 14, y: 4))
        path.curve(to: NSPoint(x: w, y: head),
                   controlPoint1: NSPoint(x: w / 2 + 14, y: 4),
                   controlPoint2: NSPoint(x: w, y: 2))
        path.line(to: NSPoint(x: w, y: h))
        path.close()
        return path
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let target else { return }
        let selected = isSelected
        let lancet = self.lancet

        NSGraphicsContext.saveGraphicsState()
        lancet.addClip()
        if selected, let glass = Gothic.image("glass") {
            NSColor(patternImage: glass).setFill()
            bounds.fill()
            NSColor.black.withAlphaComponent(0.38).setFill()
        } else {
            Gothic.nave.setFill()
            bounds.fill()
            NSColor.white.withAlphaComponent(hovering ? 0.07 : 0.03).setFill()
        }
        bounds.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()

        let tint = (target as? TerminalWindow)?.tabColor.displayColor
        (tint ?? Gothic.limestone).withAlphaComponent(selected ? 0.9 : 0.4).setStroke()
        lancet.lineWidth = selected ? 1.5 : 1
        lancet.stroke()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = .black
        shadow.shadowBlurRadius = 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Gothic.font(13),
            .foregroundColor: selected ? Gothic.parchment : Gothic.limestone.withAlphaComponent(0.6),
            .paragraphStyle: style,
            .shadow: shadow,
        ]
        NSAttributedString(string: target.title, attributes: attributes)
            .draw(in: NSRect(x: 22, y: 9, width: bounds.width - 44, height: bounds.height - 10))

        if hovering {
            let close = NSAttributedString(string: "×", attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: Gothic.limestone,
            ])
            close.draw(at: NSPoint(x: closeRect.minX + 3, y: closeRect.minY - 3))
        }
    }
}

// MARK: - Doors

/// A pair of oak doors over the terminal that swing open on their hinges
/// and then remove themselves.
final class GothicDoorsView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Never take clicks or focus from the terminal.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func open(left: NSImage, right: NSImage) {
        guard let layer else { return }

        // AppKit backing layers anchor at (0,0), which would put the
        // vanishing point in the corner. A centred stage keeps it mid-door.
        let stage = CALayer()
        stage.frame = layer.bounds
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 900
        stage.sublayerTransform = perspective
        layer.addSublayer(stage)

        let half = bounds.width / 2
        // Each leaf hinges on its outer edge and swings away from us, into the nave.
        let leaves = [(left, CGFloat(0), CGFloat(1)), (right, CGFloat(1), CGFloat(-1))].map { item in
            let (image, anchorX, swing) = item
            let leaf = CALayer()
            leaf.contents = image
            leaf.contentsGravity = .resizeAspectFill
            leaf.masksToBounds = true
            leaf.anchorPoint = CGPoint(x: anchorX, y: 0.5)
            leaf.bounds = CGRect(x: 0, y: 0, width: half, height: bounds.height)
            leaf.position = CGPoint(x: anchorX * bounds.width, y: bounds.height / 2)
            leaf.contentsScale = window?.backingScaleFactor ?? 2
            stage.addSublayer(leaf)
            return (leaf, swing)
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.removeFromSuperview() }
        for (leaf, swing) in leaves {
            let swingOpen = CABasicAnimation(keyPath: "transform.rotation.y")
            swingOpen.toValue = swing * .pi * 0.55
            swingOpen.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.3, 1)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.toValue = 0
            fade.beginTime = 0.55

            let group = CAAnimationGroup()
            group.animations = [swingOpen, fade]
            group.beginTime = CACurrentMediaTime() + 0.2
            group.duration = 0.95
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            leaf.add(group, forKey: "open")
        }
        CATransaction.commit()
    }
}
