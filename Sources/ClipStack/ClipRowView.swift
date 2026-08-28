import AppKit

/// A custom menu-item row for a history clip: icon and title on the left,
/// favourite / edit / delete buttons inline on the right (in the style of
/// Clipboard History Pro). Clicking anywhere else on the row pastes the clip.
final class ClipRowView: NSView {
    var onSelect: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Keyboard-navigation highlight, mirrored from the enclosing menu item
    /// by MenuController (custom views don't repaint on highlight by default).
    var itemHighlighted = false { didSet { refreshAppearance() } }

    private var isFavorite: Bool
    private let titleField: NSTextField
    private let favoriteButton: NSButton
    private let editButton: NSButton?
    private let deleteButton: NSButton
    private var hovered = false { didSet { refreshAppearance() } }
    private var trackingArea: NSTrackingArea?

    init(title: String, icon: NSImage?, isFavorite: Bool, canEdit: Bool, toolTip: String?) {
        self.isFavorite = isFavorite

        titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(ofSize: 0)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        favoriteButton = Self.makeButton(symbol: isFavorite ? "star.fill" : "star",
                                         description: isFavorite ? "Remove from Favourites" : "Add to Favourites")
        editButton = canEdit ? Self.makeButton(symbol: "square.and.pencil", description: "Edit") : nil
        deleteButton = Self.makeButton(symbol: "xmark", description: "Delete")

        super.init(frame: .zero)
        self.toolTip = toolTip

        favoriteButton.target = self
        favoriteButton.action = #selector(favoriteClicked)
        editButton?.target = self
        editButton?.action = #selector(editClicked)
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)

        var views: [NSView] = []
        if let icon {
            let iconView = NSImageView(image: icon)
            iconView.imageScaling = .scaleProportionallyDown
            views.append(iconView)
        }
        views.append(titleField)
        views.append(favoriteButton)
        if let editButton { views.append(editButton) }
        views.append(deleteButton)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 14, bottom: 3, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func makeButton(symbol: String, description: String) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = description
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    // MARK: Appearance

    override func draw(_ dirtyRect: NSRect) {
        guard hovered || itemHighlighted else { return }
        let rect = bounds.insetBy(dx: 5, dy: 0)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

    private func refreshAppearance() {
        let emphasized = hovered || itemHighlighted
        titleField.textColor = emphasized ? .selectedMenuItemTextColor : .labelColor
        let buttonTint: NSColor = emphasized ? .selectedMenuItemTextColor : .secondaryLabelColor
        favoriteButton.contentTintColor = isFavorite && !emphasized ? .systemYellow : buttonTint
        editButton?.contentTintColor = buttonTint
        deleteButton.contentTintColor = buttonTint
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    // MARK: Actions

    /// Clicks outside the buttons paste the clip (custom-view menu items must
    /// dismiss the menu and fire their action themselves).
    override func mouseUp(with event: NSEvent) {
        dismissMenu()
        let action = onSelect
        // Deferred so focus returns to the target app before any auto-paste.
        DispatchQueue.main.async { action?() }
    }

    @objc private func favoriteClicked() {
        // Toggles in place; the menu stays open and reorders on next open.
        isFavorite.toggle()
        favoriteButton.image = NSImage(systemSymbolName: isFavorite ? "star.fill" : "star",
                                       accessibilityDescription: isFavorite ? "Remove from Favourites" : "Add to Favourites")
        refreshAppearance()
        onToggleFavorite?()
    }

    @objc private func editClicked() {
        dismissMenu()
        let action = onEdit
        DispatchQueue.main.async { action?() }
    }

    @objc private func deleteClicked() {
        // The controller removes the clip and its menu item; menu stays open.
        onDelete?()
    }

    private func dismissMenu() {
        enclosingMenuItem?.menu?.cancelTracking()
    }
}
