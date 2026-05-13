import AppKit
import SwiftUI

class GhostWindow: NSWindow {
    var onUserFrameInteraction: (() -> Void)?
    
    init(contentRect: NSRect, contentView: NSView) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Set minimum size constraints
        self.minSize = NSSize(width: Config.minWindowWidth, height: Config.minWindowHeight)
        
        // CRITICAL: Hide from screen sharing
        self.sharingType = .none
        
        // Make window transparent
        self.backgroundColor = .clear
        self.isOpaque = false
        
        // Keep window floating above other windows
        self.level = .floating
        
        // Allow mouse events for dragging/resizing
        self.ignoresMouseEvents = false
        
        // Additional window configuration
        self.isMovableByWindowBackground = true
        self.hasShadow = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        
        // Set the content view
        self.contentView = contentView
        
        // Make window key and order front
        self.makeKeyAndOrderFront(nil)
        
        // Allow window to join all spaces
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    // Allow window to become key for interaction
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }

    override func mouseDown(with event: NSEvent) {
        makeKey()
        super.mouseDown(with: event)
    }

    func notifyUserFrameInteraction() {
        onUserFrameInteraction?()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let targetScreen = screen ?? bestScreen(for: frameRect)
        guard let visibleFrame = targetScreen?.visibleFrame else {
            return super.constrainFrameRect(frameRect, to: screen)
        }

        var constrained = frameRect
        constrained.size.width = min(max(constrained.width, minSize.width), visibleFrame.width)
        constrained.size.height = min(max(constrained.height, minSize.height), visibleFrame.height)
        constrained.origin.x = min(max(constrained.minX, visibleFrame.minX), visibleFrame.maxX - constrained.width)
        constrained.origin.y = min(max(constrained.minY, visibleFrame.minY), visibleFrame.maxY - constrained.height)
        return constrained
    }

    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let frameCenter = NSPoint(x: frame.midX, y: frame.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.visibleFrame.contains(frameCenter) }) {
            return containingScreen
        }

        return NSScreen.screens.max { lhs, rhs in
            lhs.visibleFrame.intersection(frame).area < rhs.visibleFrame.intersection(frame).area
        } ?? NSScreen.main
    }
}

// MARK: - Drag Handle View

class DragHandleView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.cornerRadius = 4
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        (window as? GhostWindow)?.notifyUserFrameInteraction()
        window?.performDrag(with: event)
    }
    
    // Draw grip lines
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        
        let centerY = bounds.height / 2
        let lineWidth: CGFloat = 20
        let startX = (bounds.width - lineWidth) / 2
        
        // Draw three horizontal lines
        for offset: CGFloat in [-3, 0, 3] {
            context.move(to: CGPoint(x: startX, y: centerY + offset))
            context.addLine(to: CGPoint(x: startX + lineWidth, y: centerY + offset))
        }
        
        context.strokePath()
    }
}

// MARK: - Corner Resize Handle (Supports All 4 Corners)

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

class CornerResizeHandle: NSView {
    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: NSRect?
    private var isHovering = false
    private var trackingArea: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private let activeEdgeSize: CGFloat = 8
    let corner: ResizeCorner
    
    init(corner: ResizeCorner) {
        self.corner = corner
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        self.corner = .bottomRight
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        alphaValue = 1.0  // Start fully visible, use isHovering for drawing changes
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        resetHover()
        installWindowObservers()
        updateTrackingAreas()
    }

    deinit {
        removeWindowObservers()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: activeRect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        setHovering(true)
    }
    
    override func mouseExited(with event: NSEvent) {
        resetHover()
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverForCurrentMouseLocation()
    }
    
    override func resetCursorRects() {
        addCursorRect(activeRect, cursor: .arrow)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        activeRect.contains(point) ? self : nil
    }
    
    override func mouseDown(with event: NSEvent) {
        guard activeRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        (window as? GhostWindow)?.notifyUserFrameInteraction()
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window?.frame
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window,
              let initialMouse = initialMouseLocation,
              let initialFrame = initialWindowFrame else { return }
        setHovering(true)
        
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - initialMouse.x
        let deltaY = currentMouse.y - initialMouse.y
        
        var newFrame = initialFrame
        
        switch corner {
        case .bottomRight:
            // Width expands right, height expands down (origin.y moves up)
            newFrame.size.width = max(initialFrame.width + deltaX, Config.minWindowWidth)
            newFrame.size.height = max(initialFrame.height - deltaY, Config.minWindowHeight)
            newFrame.origin.y = initialFrame.origin.y + initialFrame.height - newFrame.height
            
        case .bottomLeft:
            // Width expands left (origin.x moves), height expands down
            let newWidth = max(initialFrame.width - deltaX, Config.minWindowWidth)
            newFrame.size.width = newWidth
            newFrame.origin.x = initialFrame.origin.x + initialFrame.width - newWidth
            newFrame.size.height = max(initialFrame.height - deltaY, Config.minWindowHeight)
            newFrame.origin.y = initialFrame.origin.y + initialFrame.height - newFrame.height
            
        case .topRight:
            // Width expands right, height expands up
            newFrame.size.width = max(initialFrame.width + deltaX, Config.minWindowWidth)
            newFrame.size.height = max(initialFrame.height + deltaY, Config.minWindowHeight)
            
        case .topLeft:
            // Width expands left (origin.x moves), height expands up
            let newWidth = max(initialFrame.width - deltaX, Config.minWindowWidth)
            newFrame.size.width = newWidth
            newFrame.origin.x = initialFrame.origin.x + initialFrame.width - newWidth
            newFrame.size.height = max(initialFrame.height + deltaY, Config.minWindowHeight)
        }
        
        window.setFrame(window.constrainFrameRect(newFrame, to: nil), display: true)
    }
    
    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowFrame = nil
        DispatchQueue.main.async { [weak self] in
            self?.updateHoverForCurrentMouseLocation()
        }
    }

    private func installWindowObservers() {
        guard let window else { return }

        let notifications: [Notification.Name] = [
            NSWindow.didResignKeyNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didMiniaturizeNotification
        ]

        windowObservers = notifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.resetHover()
            }
        }
    }

    private func removeWindowObservers() {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
    }

    private func updateHoverForCurrentMouseLocation() {
        guard let window else {
            resetHover()
            return
        }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        setHovering(activeRect.contains(localPoint))
    }

    private func setHovering(_ newValue: Bool) {
        guard isHovering != newValue else { return }
        isHovering = newValue
        needsDisplay = true
    }

    private func resetHover() {
        setHovering(false)
    }

    private var activeRect: NSRect {
        switch corner {
        case .topLeft:
            return NSRect(x: 0, y: bounds.height - activeEdgeSize, width: activeEdgeSize, height: activeEdgeSize)
        case .topRight:
            return NSRect(x: bounds.width - activeEdgeSize, y: bounds.height - activeEdgeSize, width: activeEdgeSize, height: activeEdgeSize)
        case .bottomLeft:
            return NSRect(x: 0, y: 0, width: activeEdgeSize, height: activeEdgeSize)
        case .bottomRight:
            return NSRect(x: bounds.width - activeEdgeSize, y: 0, width: activeEdgeSize, height: activeEdgeSize)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw a subtle corner arc on every resize handle. Keeping the
        // bottom handles visually identical to the top handles prevents the
        // grip from competing with the composer controls.
        switch corner {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let lineWidth: CGFloat = isHovering ? 3.0 : 1.0
            let opacity: CGFloat = isHovering ? 0.9 : 0.15
            let color = NSColor.white.withAlphaComponent(opacity)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(lineWidth)
            
            let cornerRadius: CGFloat = 12
            
            switch corner {
            case .topLeft:
                let center = CGPoint(x: cornerRadius, y: bounds.height - cornerRadius)
                context.addArc(center: center, radius: cornerRadius - lineWidth/2,
                              startAngle: .pi, endAngle: .pi/2, clockwise: true)
            case .topRight:
                let center = CGPoint(x: bounds.width - cornerRadius, y: bounds.height - cornerRadius)
                context.addArc(center: center, radius: cornerRadius - lineWidth/2,
                              startAngle: .pi/2, endAngle: 0, clockwise: true)
            case .bottomLeft:
                let center = CGPoint(x: cornerRadius, y: cornerRadius)
                context.addArc(center: center, radius: cornerRadius - lineWidth/2,
                              startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
            case .bottomRight:
                let center = CGPoint(x: bounds.width - cornerRadius, y: cornerRadius)
                context.addArc(center: center, radius: cornerRadius - lineWidth/2,
                              startAngle: 0, endAngle: .pi * 1.5, clockwise: true)
            }
            context.strokePath()
        }
    }
}

// MARK: - Ghost Window Controller

class GhostWindowController: NSWindowController {
    private var hostingView: NSHostingView<AnyView>?
    
    convenience init<Content: View>(rootView: Content, contentRect: NSRect? = nil) {
        // Create a wrapper view (draggable by background)
        let initialRect = contentRect ?? GhostWindowController.defaultContentRect()
        let wrapperView = GhostContentView(frame: NSRect(
            x: 0,
            y: 0,
            width: initialRect.width,
            height: initialRect.height
        ))
        
        // Create the hosting view for SwiftUI content
        let hostingView = FirstMouseHostingView(rootView: AnyView(rootView))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create all 4 corner resize handles
        let bottomRight = CornerResizeHandle(corner: .bottomRight)
        let bottomLeft = CornerResizeHandle(corner: .bottomLeft)
        let topRight = CornerResizeHandle(corner: .topRight)
        let topLeft = CornerResizeHandle(corner: .topLeft)
        
        [bottomRight, bottomLeft, topRight, topLeft].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            wrapperView.addSubview($0)
        }
        
        wrapperView.addSubview(hostingView)
        // Bring resize handles to front
        [bottomRight, bottomLeft, topRight, topLeft].forEach {
            wrapperView.addSubview($0, positioned: .above, relativeTo: hostingView)
        }
        
        let handleSize: CGFloat = 20
        
        // Layout constraints
        NSLayoutConstraint.activate([
            // Hosting view fills the wrapper
            hostingView.topAnchor.constraint(equalTo: wrapperView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor),
            
            // Bottom-right resize handle
            bottomRight.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor),
            bottomRight.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor),
            bottomRight.widthAnchor.constraint(equalToConstant: handleSize),
            bottomRight.heightAnchor.constraint(equalToConstant: handleSize),
            
            // Bottom-left resize handle
            bottomLeft.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            bottomLeft.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor),
            bottomLeft.widthAnchor.constraint(equalToConstant: handleSize),
            bottomLeft.heightAnchor.constraint(equalToConstant: handleSize),
            
            // Top-right resize handle (corner glow - larger, covers corner)
            topRight.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor),
            topRight.topAnchor.constraint(equalTo: wrapperView.topAnchor),
            topRight.widthAnchor.constraint(equalToConstant: 20),
            topRight.heightAnchor.constraint(equalToConstant: 20),
            
            // Top-left resize handle (corner glow - larger, covers corner)
            topLeft.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor),
            topLeft.topAnchor.constraint(equalTo: wrapperView.topAnchor),
            topLeft.widthAnchor.constraint(equalToConstant: 20),
            topLeft.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        let window = GhostWindow(contentRect: initialRect, contentView: wrapperView)
        
        self.init(window: window)
    }

    private static func defaultContentRect() -> NSRect {
        // Calculate initial position (bottom-right corner of screen with padding)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth = Config.defaultWindowWidth
        let windowHeight = Config.defaultWindowHeight
        let windowX = screenFrame.maxX - windowWidth - 20
        let windowY = screenFrame.minY + 20

        return NSRect(
            x: windowX,
            y: windowY,
            width: windowWidth,
            height: windowHeight
        )
    }
    
    func updateContent<Content: View>(_ content: Content) {
        if let wrapperView = window?.contentView,
           let hostingView = wrapperView.subviews.compactMap({ $0 as? NSHostingView<AnyView> }).first {
            hostingView.rootView = AnyView(content)
        }
    }
}

// MARK: - Ghost Content View (Draggable)

class GhostContentView: NSView {
    private var appearanceObserver: NSObjectProtocol?
    private let tintView = PassthroughView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppearance()
    }
    
    private func setupAppearance() {
        wantsLayer = true
        setupBackgroundViews()
        layer?.cornerRadius = 12
        layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        updateOverlayAppearance()

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .overlayAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOverlayAppearance()
        }
    }

    deinit {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
        }
    }

    private func setupBackgroundViews() {
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true

        addSubview(tintView)

        NSLayoutConstraint.activate([
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func updateOverlayAppearance() {
        tintView.layer?.backgroundColor = Config.overlayBackgroundColor.cgColor
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override var isFlipped: Bool {
        return true
    }
    
    // Enable window dragging by background
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        (window as? GhostWindow)?.notifyUserFrameInteraction()
        window?.performDrag(with: event)
    }
    
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
