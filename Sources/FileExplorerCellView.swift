import AppKit
import CmuxAppKitSupportUI
import UniformTypeIdentifiers

final class FileExplorerCellView: NSTableCellView, NSTextFieldDelegate {
    private let iconView = CmuxResolvedIconImageView()
    /// Doubles as label and inline rename field. Kept as a plain `NSTextField` — not
    /// `labelWithString:` — so we can flip `isEditable` at rename time and let AppKit's
    /// field editor drive the edit. Baseline styling matches the label form (borderless,
    /// no background) so the "not editing" state reads exactly the same as before.
    private let nameLabel = NSTextField()
    private let loadingIndicator = NSProgressIndicator()
    private var trackingArea: NSTrackingArea?

    /// Original name captured when a rename begins, so `endRename(commit: false)` can
    /// restore the field cleanly.
    private var renameOriginalName: String = ""
    /// True while the field editor is active. Prevents `controlTextDidEndEditing` from
    /// firing our commit path twice — AppKit fires it on `resignFirstResponder`, which
    /// happens after we've already committed via Enter.
    private var isRenaming = false

    /// Callback fired when the user confirms a new name (`Enter` or focus loss). Nil when
    /// no rename is armed.
    var onRenameCommit: ((_ newName: String) -> Void)?
    /// Callback fired when the user cancels the rename (`Esc`).
    var onRenameCancel: (() -> Void)?

    var onHover: ((Bool) -> Void)?
    private var nameLabelTrailingToLoadingConstraint: NSLayoutConstraint!
    private var nameLabelTrailingToContainerConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconToTextConstraint: NSLayoutConstraint!
    private var loadingWidthConstraint: NSLayoutConstraint!

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        // Baseline: reads as a label. `beginRename()` flips the two `is…` flags to enter
        // the field-editor state, and `endRename` restores them. Bezel / background stay
        // off in both states so the row never grows.
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBordered = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.focusRingType = .none
        nameLabel.delegate = self

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true
        loadingIndicator.setAccessibilityIdentifier("FileExplorerLoadingIndicator")

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(loadingIndicator)

        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 16)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 16)
        iconToTextConstraint = nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        loadingWidthConstraint = loadingIndicator.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            iconToTextConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingWidthConstraint,
            loadingIndicator.heightAnchor.constraint(equalToConstant: 12),
        ])

        nameLabelTrailingToLoadingConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: loadingIndicator.leadingAnchor,
            constant: -2
        )
        nameLabelTrailingToContainerConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -2
        )
        NSLayoutConstraint.activate([
            nameLabelTrailingToLoadingConstraint,
            nameLabelTrailingToContainerConstraint
        ])
        nameLabelTrailingToLoadingConstraint.isActive = false
    }

    func configure(with node: FileExplorerNode, gitStatus: GitFileStatus? = nil) {
        assert(Thread.isMainThread, "AppKit image updates must run on the main thread")
        let style = FileExplorerStyle.current
        nameLabel.stringValue = node.name
        nameLabel.font = style.nameFont
        iconWidthConstraint.constant = style.iconSize
        iconHeightConstraint.constant = style.iconSize
        iconToTextConstraint.constant = style.iconToTextSpacing

        if style == .finder {
            // Native Finder icon pixels miss 3:1 in light mode; use their masks with the dynamic palette tint.
            if node.isDirectory {
                iconView.apply(CmuxResolvedIconRequest(
                    source: .image(NSWorkspace.shared.icon(for: .folder)),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.folderIconTint
                ))
            } else {
                let pathExtension = (node.name as NSString).pathExtension
                iconView.apply(CmuxResolvedIconRequest(
                    source: .image(NSWorkspace.shared.icon(for: UTType(filenameExtension: pathExtension) ?? .data)),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.fileIconTint
                ))
            }
        } else {
            if node.isDirectory {
                iconView.apply(CmuxResolvedIconRequest(
                    source: .systemSymbol(name: "folder.fill", accessibilityDescription: nil),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.folderIconTint,
                    symbolWeight: style.iconWeight
                ))
            } else {
                iconView.apply(CmuxResolvedIconRequest(
                    source: .systemSymbol(name: "doc", accessibilityDescription: nil),
                    size: NSSize(width: style.iconSize, height: style.iconSize),
                    tintColor: style.fileIconTint,
                    symbolWeight: style.iconWeight
                ))
            }
        }

        if node.isLoading {
            loadingWidthConstraint.constant = 12
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
            nameLabelTrailingToLoadingConstraint.isActive = true
            nameLabelTrailingToContainerConstraint.isActive = false
        } else {
            loadingWidthConstraint.constant = 0
            loadingIndicator.isHidden = true
            loadingIndicator.stopAnimation(nil)
            nameLabelTrailingToLoadingConstraint.isActive = false
            nameLabelTrailingToContainerConstraint.isActive = true
        }

        if let error = node.error {
            nameLabel.textColor = .systemRed
            nameLabel.toolTip = error
        } else if let gitStatus {
            nameLabel.textColor = style.gitColor(for: gitStatus)
            nameLabel.toolTip = node.path
        } else {
            nameLabel.textColor = .labelColor
            nameLabel.toolTip = node.path
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    // MARK: - Inline rename

    /// Puts the row into VS Code-style inline rename: the name label becomes an editable
    /// field, focus lands on it, and the file name is selected up to (but excluding) its
    /// extension so a quick retype only overwrites the base name.
    func beginRename() {
        guard let window else { return }
        renameOriginalName = nameLabel.stringValue
        nameLabel.isEditable = true
        nameLabel.isSelectable = true
        isRenaming = true
        _ = window.makeFirstResponder(nameLabel)
        selectRenameBaseName()
    }

    private func selectRenameBaseName() {
        guard let editor = nameLabel.currentEditor() else { return }
        let name = renameOriginalName as NSString
        let ext = name.pathExtension
        if !ext.isEmpty, name.length > ext.count + 1 {
            editor.selectedRange = NSRange(location: 0, length: name.length - ext.count - 1)
        } else {
            editor.selectAll(nil)
        }
    }

    private func endRename(commit: Bool) {
        guard isRenaming else { return }
        isRenaming = false
        let value = nameLabel.stringValue
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        if commit,
           !value.isEmpty,
           value != renameOriginalName {
            onRenameCommit?(value)
        } else {
            // Restoring the original text before firing the cancel callback matters: the
            // label is what the row shows during the next runloop turn, before the outline
            // reload landing new node names.
            nameLabel.stringValue = renameOriginalName
            onRenameCancel?()
        }
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            endRename(commit: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(commit: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Clicking away is also a commit — consistent with Finder and VS Code. `endRename`
        // is idempotent because `isRenaming` gates it.
        endRename(commit: true)
    }
}
