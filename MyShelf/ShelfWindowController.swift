import Cocoa

class ShelfWindowController: NSWindowController, NSWindowDelegate {

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.backgroundColor = Self.bgColor

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = Self.bgColor.cgColor
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true

        let shelf = ShelfView(frame: .zero)
        shelf.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(shelf)
        NSLayoutConstraint.activate([
            shelf.topAnchor.constraint(equalTo: container.topAnchor),
            shelf.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            shelf.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            shelf.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        window.contentView = container

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Show / Hide

    func toggleShelf() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showShelf(at mousePosition: NSPoint) {
        guard let window = window else { return }

        let size = window.frame.size
        var origin = NSPoint(
            x: mousePosition.x + 12,
            y: mousePosition.y - size.height - 12
        )

        let screen = NSScreen.screens.first { $0.frame.contains(mousePosition) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
            origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        }

        window.setFrameOrigin(origin)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Resize helpers

    func resizeWindow(to size: NSSize, animated: Bool) {
        guard let window = window else { return }
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        let newFrame = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        shelfView?.clearItems()
    }

    private static let bgColor = NSColor(red: 60/255, green: 60/255, blue: 62/255, alpha: 1)

    private var shelfView: ShelfView? {
        window?.contentView?.subviews.first as? ShelfView
    }
}
