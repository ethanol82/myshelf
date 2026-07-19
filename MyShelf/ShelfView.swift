import Cocoa
import QuickLookThumbnailing

// MARK: - DragHandleView

private class DragHandleView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - ShelfCellView

private class ShelfCellView: NSView {
    let iconView = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    var isHovering = false { didSet { refreshBg() } }
    var isSelected = false { didSet { refreshBg() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        refreshBg()

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 9, weight: .medium)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        nameLabel.alignment = .center
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.cell?.truncatesLastVisibleLine = true

        addSubview(iconView)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refreshBg() {
        let bg: NSColor
        if isSelected      { bg = NSColor(red: 96/255, green: 96/255, blue: 98/255, alpha: 1) }
        else if isHovering { bg = NSColor(red: 85/255, green: 85/255, blue: 87/255, alpha: 1) }
        else               { bg = NSColor(red: 74/255, green: 74/255, blue: 76/255, alpha: 1) }
        layer?.backgroundColor = bg.cgColor
        layer?.borderWidth = isSelected ? 1.5 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent)  { isHovering = false }
}

// MARK: - ShelfItemCollectionViewItem

private class ShelfItemCollectionViewItem: NSCollectionViewItem {
    private var currentURL: URL?

    var cellView: ShelfCellView { view as! ShelfCellView }

    override func loadView() {
        view = ShelfCellView(frame: NSRect(x: 0, y: 0, width: 70, height: 70))
    }

    func configure(with url: URL) {
        currentURL = url
        let cv = cellView
        cv.nameLabel.stringValue = url.deletingPathExtension().lastPathComponent
        cv.toolTip = url.path
        cv.iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        cv.iconView.layer?.cornerRadius = 0
        cv.iconView.layer?.masksToBounds = false

        let ext = url.pathExtension.lowercased()
        if ["jpg","jpeg","png","gif","tiff","tif","bmp","heic","heif","pdf","svg","webp"].contains(ext) {
            generateThumbnail(for: url)
        }
    }

    private func generateThumbnail(for url: URL) {
        let size = CGSize(width: 72, height: 72)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(
            fileAt: url, size: size, scale: scale, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep = rep else { return }
            let img = rep.nsImage
            DispatchQueue.main.async {
                guard self?.currentURL == url else { return }
                self?.cellView.iconView.image = img
                self?.cellView.iconView.layer?.cornerRadius = 4
                self?.cellView.iconView.layer?.masksToBounds = true
            }
        }
    }

    override var isSelected: Bool {
        didSet { cellView.isSelected = isSelected }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { cellView.isHovering = highlightState == .forSelection }
    }
}

// MARK: - ShelfView

class ShelfView: NSView {

    private enum State { case empty, hasItems }
    private var viewState: State = .empty

    private static let cell:   CGFloat = 70
    private static let gap:    CGFloat = 8
    private static let hPad:   CGFloat = 16
    private static let vPad:   CGFloat = 14
    private static let hdrH:   CGFloat = 28
    private static let maxRows = 4
    private static let emptySize = NSSize(width: 200, height: 160)
    private static let itemID = NSUserInterfaceItemIdentifier("ShelfItem")

    // MARK: Data

    private var storedURLs: [URL] = []

    // MARK: Subviews — empty state

    private let emptyContainer: NSView = {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    private let dashedBox: DashedBorderView = {
        let v = DashedBorderView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    private let dropArrow: NSImageView = {
        let iv = NSImageView()
        iv.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        iv.contentTintColor = NSColor.white.withAlphaComponent(0.3)
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let dropLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "drop files here")
        tf.font = .systemFont(ofSize: 11)
        tf.textColor = NSColor.white.withAlphaComponent(0.4)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    // MARK: Subviews — file state

    private let fileContainer: NSView = {
        let v = NSView(); v.translatesAutoresizingMaskIntoConstraints = false
        v.alphaValue = 0; return v
    }()
    private let headerView: DragHandleView = {
        let v = DragHandleView(); v.translatesAutoresizingMaskIntoConstraints = false; return v
    }()
    private let countLabel: NSTextField = {
        let tf = NSTextField(labelWithString: "0 ITEMS")
        tf.font = .systemFont(ofSize: 11, weight: .semibold)
        tf.textColor = NSColor.white.withAlphaComponent(0.6)
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    private lazy var trashButton = makeHeaderBtn(symbol: "trash",  action: #selector(clearAllTapped))
    private lazy var closeButton = makeHeaderBtn(symbol: "xmark",  action: #selector(closeTapped))

    private let scrollView: NSScrollView = {
        let sv = NSScrollView()
        sv.hasVerticalScroller = true; sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true; sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let collectionView: NSCollectionView = {
        let cv = NSCollectionView()
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.allowsEmptySelection = true
        cv.backgroundColors = [.clear]
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 70, height: 70)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        cv.collectionViewLayout = layout
        return cv
    }()

    // MARK: Init

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        setupEmptyState()
        setupFileState()

        collectionView.dataSource = self
        collectionView.delegate   = self
        collectionView.register(ShelfItemCollectionViewItem.self, forItemWithIdentifier: Self.itemID)
        collectionView.setDraggingSourceOperationMask(.every, forLocal: false)
        collectionView.setDraggingSourceOperationMask(.every, forLocal: true)

        registerForDraggedTypes([.fileURL])
        transition(to: .empty, animated: false)
    }

    // MARK: - Layout setup

    private func setupEmptyState() {
        addSubview(emptyContainer)
        emptyContainer.addSubview(dashedBox)
        dashedBox.addSubview(dropArrow)
        dashedBox.addSubview(dropLabel)

        NSLayoutConstraint.activate([
            emptyContainer.topAnchor.constraint(equalTo: topAnchor),
            emptyContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            dashedBox.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            dashedBox.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor),
            dashedBox.widthAnchor.constraint(equalTo: emptyContainer.widthAnchor, constant: -64),
            dashedBox.heightAnchor.constraint(equalToConstant: 88),

            dropArrow.centerXAnchor.constraint(equalTo: dashedBox.centerXAnchor),
            dropArrow.topAnchor.constraint(equalTo: dashedBox.topAnchor, constant: 18),
            dropArrow.widthAnchor.constraint(equalToConstant: 22),
            dropArrow.heightAnchor.constraint(equalToConstant: 22),

            dropLabel.centerXAnchor.constraint(equalTo: dashedBox.centerXAnchor),
            dropLabel.topAnchor.constraint(equalTo: dropArrow.bottomAnchor, constant: 8),
        ])
    }

    private func setupFileState() {
        trashButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(fileContainer)
        fileContainer.addSubview(headerView)
        headerView.addSubview(countLabel)
        headerView.addSubview(trashButton)
        headerView.addSubview(closeButton)
        fileContainer.addSubview(scrollView)
        scrollView.documentView = collectionView

        NSLayoutConstraint.activate([
            fileContainer.topAnchor.constraint(equalTo: topAnchor),
            fileContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            fileContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            fileContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerView.topAnchor.constraint(equalTo: fileContainer.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: fileContainer.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: fileContainer.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            countLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            countLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),

            trashButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -5),
            trashButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            trashButton.widthAnchor.constraint(equalToConstant: 18),
            trashButton.heightAnchor.constraint(equalToConstant: 18),

            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: fileContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: fileContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: fileContainer.bottomAnchor),
        ])
    }

    // MARK: - Column / window size helpers

    private func colCount() -> Int { min(max(storedURLs.count, 1), 3) }
    private func rowCount() -> Int {
        let c = colCount(); return (storedURLs.count + c - 1) / c
    }

    private func computeWindowSize() -> NSSize {
        guard !storedURLs.isEmpty else { return Self.emptySize }
        let c = CGFloat(colCount())
        let r = CGFloat(min(rowCount(), Self.maxRows))
        let w = c * Self.cell + (c - 1) * Self.gap + Self.hPad * 2
        let h = Self.hdrH + Self.vPad + r * Self.cell + (r - 1) * Self.gap + Self.vPad
        return NSSize(width: w, height: h)
    }

    // MARK: - State & layout refresh

    private func transition(to newState: State, animated: Bool) {
        viewState = newState
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.2 : 0
            switch newState {
            case .empty:
                emptyContainer.animator().alphaValue = 1
                fileContainer.animator().alphaValue  = 0
            case .hasItems:
                emptyContainer.animator().alphaValue = 0
                fileContainer.animator().alphaValue  = 1
            }
        }
        refreshLayout(animated: animated)
    }

    private func refreshLayout(animated: Bool) {
        let targetSize = computeWindowSize()

        // Resize collection view to target width so FlowLayout computes correct columns
        let contentH: CGFloat
        if storedURLs.isEmpty {
            contentH = 0
        } else {
            let rows = CGFloat(rowCount())
            contentH = Self.vPad + rows * Self.cell + (rows - 1) * Self.gap + Self.vPad
        }
        collectionView.frame = NSRect(x: 0, y: 0, width: targetSize.width, height: contentH)
        collectionView.reloadData()

        countLabel.stringValue = storedURLs.count == 1 ? "1 ITEM" : "\(storedURLs.count) ITEMS"

        guard let wc = window?.windowController as? ShelfWindowController else { return }
        wc.resizeWindow(to: targetSize, animated: animated)
    }

    // MARK: - Public API

    func addItem(url: URL) {
        guard !storedURLs.contains(url) else { return }
        storedURLs.append(url)
        if viewState != .hasItems {
            transition(to: .hasItems, animated: true)
        } else {
            refreshLayout(animated: true)
        }
        scrollToBottom()
    }

    func clearItems() {
        storedURLs.removeAll()
        collectionView.deselectAll(nil)
        transition(to: .empty, animated: true)
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let sv = self?.scrollView,
                  let dv = sv.documentView else { return }
            let pt = NSPoint(x: 0, y: max(0, dv.frame.height - sv.contentSize.height))
            sv.contentView.scroll(to: pt)
        }
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "a" {
            collectionView.selectAll(nil)
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Drag destination (files dropped INTO shelf)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Ignore drags that originate from our own collection view
        if (sender.draggingSource as? NSCollectionView) === collectionView { return [] }
        guard canAcceptDrag(sender) else { return [] }
        setDragHighlight(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setDragHighlight(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDragHighlight(false)
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }
        urls.forEach { addItem(url: $0) }
        return true
    }

    private func canAcceptDrag(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func setDragHighlight(_ on: Bool) {
        layer?.borderWidth = on ? 2 : 0
        layer?.borderColor = on ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
    }

    // MARK: - Button actions

    @objc private func clearAllTapped() { clearItems() }
    @objc private func closeTapped()    { window?.close() }

    // MARK: - Helper

    private func makeHeaderBtn(symbol: String, action: Selector) -> NSButton {
        let btn = NSButton()
        btn.isBordered = false; btn.target = self; btn.action = action
        btn.wantsLayer = true; btn.layer?.cornerRadius = 4
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        let cfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        btn.contentTintColor = NSColor.white.withAlphaComponent(0.6)
        return btn
    }
}

// MARK: - NSCollectionViewDataSource

extension ShelfView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        storedURLs.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.itemID, for: indexPath)
        guard let shelfItem = item as? ShelfItemCollectionViewItem else { return item }
        shelfItem.configure(with: storedURLs[indexPath.item])
        return shelfItem
    }
}

// MARK: - NSCollectionViewDelegate (drag source)

extension ShelfView: NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView,
                        canDragItemsAt indexes: IndexSet,
                        with event: NSEvent) -> Bool { true }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt index: Int) -> (NSPasteboardWriting & NSObjectProtocol)? {
        guard index < storedURLs.count else { return nil }
        return storedURLs[index] as NSURL
    }
}

// MARK: - DashedBorderView

private class DashedBorderView: NSView {
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.sublayers?.removeAll()
        let shape = CAShapeLayer()
        shape.frame = bounds
        shape.path = CGPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerWidth: 10, cornerHeight: 10, transform: nil
        )
        shape.fillColor   = NSColor.clear.cgColor
        shape.strokeColor = NSColor.white.withAlphaComponent(0.2).cgColor
        shape.lineWidth   = 1.5
        shape.lineDashPattern = [6, 4]
        layer?.addSublayer(shape)
    }
}
