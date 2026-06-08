import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// Quick-send composer hosted in the non-activating panel: type a (multi-line)
/// message, pick the target from the bottom-left switcher, and fire it with
/// ⌘/⇧-Return — or jump to the agent in the main app via "Open in Prowl".
struct QuickSendView: View {
  @Bindable var store: StoreOf<QuickSendFeature>
  @State private var showingPicker = false
  /// Skill names offered as `/`-command completions in the composer, resolved from
  /// the configured skills directory (or the selected agent's default) on appear and
  /// whenever the target agent changes.
  @State private var skillNames: [String] = []
  /// Files offered as `@` completions in the composer, resolved from the selected
  /// agent's owning worktree root so accepted paths are relative to that root.
  @State private var fileReferences: [QuickSendFileReference] = []
  /// Current panel height, observed so the layout can collapse to a compact bar
  /// when the window is dragged short (or set via Collapse) below `collapseThreshold`.
  @State private var panelHeight: CGFloat = 0
  /// Resizes the hosting panel between its expanded and collapsed heights. Injected
  /// by `QuickSendPanelManager` (the `NSPanel` owner); a no-op in previews/tests.
  var onSetExpanded: (Bool) -> Void = { _ in }

  /// Height below which the panel renders the collapsed bar (agent row + Expand)
  /// instead of the full composer. Sits between the panel's collapsed (84) and
  /// expanded (260) heights (see `QuickSendPanelManager.Layout`) so dragging the
  /// window short collapses it.
  private static let collapseThreshold: CGFloat = 90

  /// Alpha of the repository-color identity wash over the panel material,
  /// matching the focused canvas-card tint in `CanvasCardView.titleBarBackground`
  /// so the composer and the main view read as the same surface family.
  private static let repositoryTintOpacity = 0.18

  /// Collapsed once the window is short enough (and after the first height
  /// measurement — `panelHeight` starts at 0, so the panel opens expanded).
  private var isCollapsed: Bool {
    panelHeight > 0 && panelHeight < Self.collapseThreshold
  }

  /// The panel's content: the compact bar when collapsed, the full composer when
  /// expanded. The window height (observed in `body`) decides which one renders.
  @ViewBuilder
  private var panelContent: some View {
    if isCollapsed {
      collapsedBar
    } else {
      VStack(alignment: .leading, spacing: 16) {
        header
        composer
        footer
      }
      .padding(20)
    }
  }

  var body: some View {
    panelContent
      .frame(minWidth: 120, maxWidth: .infinity, minHeight: 64, maxHeight: .infinity)
      .background(panelBackground)
      .clipShape(.rect(cornerRadius: 12))
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        panelHeight = $0
      }
      .task(id: store.selectedAgentID) {
        skillNames = []
        fileReferences = []
        let selectedAgent = store.selectedAgent
        let completionRoot = QuickSendFileReferences.rootDirectory(
          workingDirectory: selectedAgent?.workingDirectory,
          fallbackWorktreePath: selectedAgent?.worktreeID
        )
        let configured = UserDefaults.standard.string(forKey: QuickSendSkills.directorySettingKey) ?? ""
        let directories = QuickSendSkills.directories(
          for: store.selectedAgent?.agent,
          configured: configured,
          workingDirectory: selectedAgent?.workingDirectory
        )
        async let resolvedSkillNames: [String] = Task.detached(priority: .utility) {
          QuickSendSkills.skillNames(inAny: directories)
        }.value
        async let resolvedFileReferences: [QuickSendFileReference] = Task.detached(priority: .utility) {
          guard let completionRoot else { return [] }
          return QuickSendFileReferences.references(in: completionRoot)
        }.value

        let nextSkillNames = await resolvedSkillNames
        let nextFileReferences = await resolvedFileReferences
        guard !Task.isCancelled else { return }
        skillNames = nextSkillNames
        fileReferences = nextFileReferences
      }
  }

  /// Compact parked state: the selected-agent row plus an Expand button that grows
  /// the panel back to the full composer. Shown when the window is short
  /// (`isCollapsed`); the composer's draft lives in the store, so it survives the
  /// collapse/expand round-trip.
  private var collapsedBar: some View {
    HStack(spacing: 8) {
      agentSwitcher
      Spacer(minLength: 8)
      Button {
        onSetExpanded(true)
      } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
      }
      .buttonStyle(.borderless)
      .help("Expand to compose a message")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  /// Panel surface: the `.regularMaterial` substrate washed with the selected
  /// agent's repository color — the same identity tint the main view paints on
  /// canvas cards (`CanvasCardView.titleBarBackground`). It recomputes whenever
  /// `selectedRepositoryColor` changes, so switching the target in the
  /// bottom-left switcher restyles the panel automatically.
  @ViewBuilder
  private var panelBackground: some View {
    ZStack {
      Rectangle().fill(.regularMaterial)
      if let tint = store.selectedRepositoryColor?.color {
        tint.opacity(Self.repositoryTintOpacity)
      }
    }
  }

  /// Skill-completion trigger for the selected agent: Codex invokes skills with
  /// `$name`, every other agent (Claude, …) uses `/name`. Drives both the token the
  /// popup recognises and the text inserted on accept.
  private var skillTrigger: String {
    store.selectedAgent?.agent == .codex ? "$" : "/"
  }

  /// Shown only when expanded (the collapsed bar omits it): panel title, a one-line
  /// hint, and the Open-in-Prowl jump-to-agent button.
  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Send to Agent")
          .font(.title3)
        Text("Sends a message to the selected agent's pane. ⌘↩ to send.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button {
        store.send(.openInProwl)
      } label: {
        Label("Open in Prowl", systemImage: "arrow.up.forward.app")
          .font(.caption)
      }
      .buttonStyle(.borderless)
      .disabled(store.selectedAgent == nil)
      .help("Bring Prowl forward and focus the selected agent")
    }
  }

  private var composer: some View {
    QuickSendComposer(
      text: $store.draft,
      skillNames: skillNames,
      skillTrigger: skillTrigger,
      fileReferences: fileReferences,
      onSubmit: { store.send(.submit) },
      onCancel: { store.send(.cancel) }
    )
    .frame(maxHeight: .infinity)
    .overlay(alignment: .topLeading) {
      if store.draft.isEmpty {
        Text("Message to send…")
          .foregroundStyle(.tertiary)
          .padding(.leading, 9)
          .padding(.top, 7)
          .allowsHitTesting(false)
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 10) {
      agentSwitcher
      Spacer(minLength: 8)
      Button {
        onSetExpanded(false)
      } label: {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
      }
      .buttonStyle(.borderless)
      .help("Collapse to the compact bar")
      Button("Cancel") { store.send(.cancel) }
        .help("Cancel (Esc)")
      Button("Send") { store.send(.submit) }
        .buttonStyle(.borderedProminent)
        .disabled(!store.canSend)
        .help("Send (⌘↩)")
    }
  }

  /// Bottom-left target picker — shows the selected agent (Active-Agents row
  /// styling) and opens a popover list to switch targets without leaving the
  /// composer.
  @ViewBuilder
  private var agentSwitcher: some View {
    if let selected = store.selectedAgent {
      Button {
        showingPicker = true
      } label: {
        QuickSendAgentRow(
          entry: selected,
          display: store.displays[selected.id],
          // The bottom-left chip just shows the current target — no accent fill
          // (that highlight is reserved for the selected row in the picker popover).
          isSelected: false,
          showsChevron: store.agents.count > 1
        )
        .frame(maxWidth: 260, alignment: .leading)
      }
      .buttonStyle(.plain)
      .disabled(store.agents.count <= 1)
      .popover(isPresented: $showingPicker, arrowEdge: .top) { agentPicker }
    } else {
      Text("No active agent")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var agentPicker: some View {
    VStack(spacing: 2) {
      ForEach(store.agents) { entry in
        Button {
          store.send(.selectAgent(entry.id))
          showingPicker = false
        } label: {
          QuickSendAgentRow(
            entry: entry,
            display: store.displays[entry.id],
            isSelected: entry.id == store.selectedAgentID,
            showsChevron: false
          )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(6)
    .frame(width: 300)
  }
}

/// Hosts the quick-send composer inside the panel, scoped to the optional child
/// state. Renders nothing when no quick-send is active (the panel is ordered out
/// by `QuickSendPanelManager`).
struct QuickSendPanelRoot: View {
  let store: StoreOf<AppFeature>
  /// Forwarded to `QuickSendView` so its Expand button can resize the hosting panel.
  var onSetExpanded: (Bool) -> Void = { _ in }

  var body: some View {
    if let childStore = store.scope(state: \.quickSend, action: \.quickSend) {
      QuickSendView(store: childStore, onSetExpanded: onSetExpanded)
    }
  }
}

/// An Active-Agents-styled row (icon · "[state] branch" · repo subtitle) reused
/// for both the bottom-left switcher chip and the popover list. Selected rows
/// fill with the accent color to match the Active Agents list selection.
private struct QuickSendAgentRow: View {
  let entry: ActiveAgentEntry
  let display: ActiveAgentRowDisplay?
  let isSelected: Bool
  var showsChevron = false

  var body: some View {
    HStack(spacing: 8) {
      AgentIconImage(entry: entry)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          Text("[\(entry.displayState.label)]")
            .foregroundStyle(stateColor)
          Text(display?.branchName ?? entry.worktreeName)
            .foregroundStyle(primaryColor)
        }
        .font(.callout.weight(.medium))
        .lineLimit(1)
        Text(display?.repositoryName ?? entry.worktreeName)
          .font(.caption)
          .foregroundStyle(secondaryColor)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      if showsChevron {
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
          .foregroundStyle(secondaryColor)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .contentShape(.rect)
    .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 6))
  }

  private var primaryColor: Color { isSelected ? .white : .primary }
  private var secondaryColor: Color { isSelected ? Color.white.opacity(0.8) : .secondary }
  private var stateColor: Color { isSelected ? .white : entry.displayState.foregroundStyle }
}

/// Multi-line composer backed by `NSTextView` so plain Return inserts a newline
/// while ⌘/⇧-Return submits and Esc cancels — the same key-handling approach the
/// command palette uses (`NSViewRepresentable` over `@FocusState`, which the
/// codebase has found unreliable when focus must move onto a live `NSView`).
private struct QuickSendComposer: NSViewRepresentable {
  @Binding var text: String
  var skillNames: [String] = []
  /// `$` for Codex, `/` for Claude/others — see `QuickSendView.skillTrigger`.
  var skillTrigger: String = "/"
  var fileReferences: [QuickSendFileReference] = []
  let onSubmit: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = ComposerTextView()
    textView.delegate = context.coordinator
    textView.onSubmit = onSubmit
    textView.onCancel = onCancel
    textView.font = NSFont.preferredFont(forTextStyle: .body)
    textView.isRichText = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 4, height: 6)
    textView.string = text
    // Accept image + file drops on top of NSTextView's defaults, so a dropped image
    // becomes a path the agent can read (see `ComposerTextView.paste`).
    textView.registerForDraggedTypes(textView.registeredDraggedTypes + [.fileURL, .png, .tiff])
    textView.skillNames = skillNames
    textView.skillTrigger = skillTrigger
    textView.fileReferences = fileReferences

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? ComposerTextView else { return }
    textView.onSubmit = onSubmit
    textView.onCancel = onCancel
    let completionSourcesChanged =
      textView.skillNames != skillNames || textView.skillTrigger != skillTrigger
      || textView.fileReferences != fileReferences
    textView.skillNames = skillNames
    textView.skillTrigger = skillTrigger
    textView.fileReferences = fileReferences
    context.coordinator.text = $text
    if textView.string != text {
      textView.string = text
    }
    if completionSourcesChanged {
      textView.refreshCompletion()
    }
    // Focus the field whenever the panel is showing but it isn't first responder
    // yet — covers first appearance AND every re-show (the panel is reused, so a
    // one-time flag would skip focus on the second open). A no-op while the user
    // is typing, since the field is already first responder then.
    if let window = textView.window, window.firstResponder !== textView {
      window.makeFirstResponder(textView)
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }

  final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    /// Floating token autocomplete popup; see `SkillCompletionController`.
    private let completion = SkillCompletionController()
    /// Set while we programmatically replace a token on accept, so the resulting
    /// text change doesn't immediately reopen the popup.
    private var isInsertingCompletion = false

    override func keyDown(with event: NSEvent) {
      let isReturn = event.keyCode == 36 || event.keyCode == 76
      let hasSubmitModifier = !event.modifierFlags.intersection([.command, .shift]).isEmpty
      if isReturn, hasSubmitModifier {
        onSubmit?()
        return
      }
      // While the completion popup is open, arrow/return/tab drive it instead of the text
      // view; Esc (in `cancelOperation`) dismisses it before cancelling the composer.
      if completion.isVisible {
        switch event.keyCode {
        case 125:
          completion.moveSelection(by: 1)
          return  // ↓
        case 126:
          completion.moveSelection(by: -1)
          return  // ↑
        case 36, 76, 48:
          acceptCompletion()
          return  // Return / Enter / Tab
        case 123, 124: completion.hide()  // ← / → : dismiss, then move the caret
        default: break
        }
      }
      super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
      if completion.isVisible {
        completion.hide()
        return
      }
      onCancel?()
    }

    override func mouseDown(with event: NSEvent) {
      completion.hide()
      super.mouseDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
      completion.hide()
      return super.resignFirstResponder()
    }

    // MARK: - Token completion

    var skillNames: [String] = []
    /// Skill-completion trigger char for the current agent: `$` (Codex) or `/`
    /// (Claude/others). Set from `QuickSendView.skillTrigger`.
    var skillTrigger: String = "/"
    var fileReferences: [QuickSendFileReference] = []

    /// Recompute the popup after any text change (typing, delete, paste). Skipped
    /// while inserting a chosen completion, so accepting doesn't reopen it.
    override func didChangeText() {
      super.didChangeText()
      guard !isInsertingCompletion else { return }
      updateCompletion()
    }

    func refreshCompletion() {
      guard !isInsertingCompletion else { return }
      updateCompletion()
    }

    /// Shows, updates, or hides the floating popup based on the `/command` or
    /// `@file` token under the caret and the available completion sources.
    private func updateCompletion() {
      guard let token = completionToken(), let window else {
        completion.hide()
        return
      }
      let matches = completionItems(for: token)
      guard !matches.isEmpty else {
        completion.hide()
        return
      }
      // Anchor under the token's trigger (stable as the query grows; the first
      // line fragment if it wraps). `firstRect` reports screen coordinates — the space
      // the popup is positioned in. A `.zero` rect means the glyph isn't laid out yet,
      // so skip rather than place the popup at the screen origin.
      let anchor = firstRect(
        forCharacterRange: NSRange(location: token.range.location, length: 0), actualRange: nil)
      guard anchor != .zero else {
        completion.hide()
        return
      }
      completion.show(matches: matches, below: anchor, parent: window)
    }

    /// Replaces the token under the caret with the highlighted completion, then hides.
    private func acceptCompletion() {
      guard let item = completion.selectedCompletion, let token = completionToken() else {
        completion.hide()
        return
      }
      isInsertingCompletion = true
      insertText(item.insertionText, replacementRange: token.range)
      isInsertingCompletion = false
      completion.hide()
    }

    private func completionItems(for token: CompletionToken) -> [QuickSendCompletionItem] {
      switch token.trigger {
      case .skill:
        guard !skillNames.isEmpty else { return [] }
        let query = token.query.lowercased()
        return
          skillNames
          .filter { query.isEmpty || $0.lowercased().contains(query) }
          .map {
            QuickSendCompletionItem(
              id: "skill.\($0)",
              title: $0,
              subtitle: nil,
              insertionText: "\(skillTrigger)\($0)",
              systemImage: "puzzlepiece.extension.fill"
            )
          }
      case .file:
        guard !fileReferences.isEmpty else { return [] }
        return QuickSendFileReferences.rankedMatches(in: fileReferences, query: token.query)
          .map { reference in
            // Directories insert with a trailing slash so the agent can tell a folder
            // reference from a file one; both keep a trailing space so the user can
            // keep typing after the inserted token.
            let path = reference.isDirectory ? "\(reference.relativePath)/" : reference.relativePath
            return QuickSendCompletionItem(
              id: "\(reference.isDirectory ? "dir" : "file").\(reference.relativePath)",
              title: reference.fileName,
              subtitle: reference.parentPath,
              insertionText: "@\(path) ",
              systemImage: reference.isDirectory ? "folder" : "doc.text"
            )
          }
      }
    }

    /// The skill (`/` or `$`, per `skillTrigger`) or `@file` token under the caret
    /// (the trigger must start the current whitespace-delimited word), or nil.
    /// Anchoring to the word start is what stops slashes inside normal paths (`a/b`)
    /// and a mid-word `@` from spuriously triggering completion.
    private func completionToken() -> CompletionToken? {
      let text = string as NSString
      let caret = selectedRange().location
      guard caret != NSNotFound, caret > 0, caret <= text.length else { return nil }
      var start = caret
      while start > 0 {
        let ch = text.substring(with: NSRange(location: start - 1, length: 1))
        if ch.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { break }
        start -= 1
      }
      guard caret - start > 0 else { return nil }
      let token = text.substring(with: NSRange(location: start, length: caret - start))
      let range = NSRange(location: start, length: caret - start)
      if token.hasPrefix(skillTrigger) {
        return CompletionToken(trigger: .skill, range: range, query: String(token.dropFirst()))
      }
      if token.hasPrefix("@") {
        return CompletionToken(trigger: .file, range: range, query: String(token.dropFirst()))
      }
      return nil
    }

    private enum CompletionTrigger {
      case skill
      case file
    }

    private struct CompletionToken {
      let trigger: CompletionTrigger
      let range: NSRange
      let query: String
    }

    // NSTextView enables the Paste command (⌘V and the context-menu item) only when
    // the clipboard's types intersect `readablePasteboardTypes`; a plain-text view
    // omits image/file types, so an image-only clipboard leaves Paste disabled and the
    // event never reaches `paste(_:)`. Advertise the image/file types so the command
    // stays enabled — `paste(_:)` below then turns them into a path.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
      super.readablePasteboardTypes + [.png, .tiff, .fileURL]
    }

    // Terminal agents (e.g. Claude Code) read images from a file PATH in the prompt,
    // so an image pasted or dropped here is turned into a path the agent can read,
    // then sent as part of the message. An image FILE keeps its real path; raw image
    // data (a clipboard screenshot) is written to a temp PNG first. Non-image content
    // falls through to the normal plain-text behavior.
    override func paste(_ sender: Any?) {
      if insertImagePaths(from: NSPasteboard.general) { return }
      super.paste(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
      if insertImagePaths(from: sender.draggingPasteboard) { return true }
      return super.performDragOperation(sender)
    }

    /// Inserts a path for any image carried by `pasteboard` at the caret, returning
    /// whether it handled one. Image files use their existing path; raw image data is
    /// written to a temp file first.
    private func insertImagePaths(from pasteboard: NSPasteboard) -> Bool {
      if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
        // Only local image FILES keep their real path; a web URL (e.g. an image
        // copied from a browser) falls through to be materialized below.
        let paths = urls.filter { $0.isFileURL && isImageFile($0) }.map(\.path)
        if !paths.isEmpty {
          insertPaths(paths)
          return true
        }
      }
      guard let data = pngData(from: pasteboard), let path = writeTempImage(data) else {
        return false
      }
      insertPaths([path])
      return true
    }

    private func insertPaths(_ paths: [String]) {
      // Trailing space so the user can keep typing after the inserted path(s).
      insertText(paths.joined(separator: " ") + " ", replacementRange: selectedRange())
    }

    private func isImageFile(_ url: URL) -> Bool {
      UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// PNG bytes from the pasteboard — direct PNG when present (e.g. screenshots),
    /// otherwise materialized via `NSImage`, which reads whatever the pasteboard
    /// carries: flat TIFF data OR an `NSImage` object (some apps write the image as
    /// an object rather than flat data, which `data(forType:)` can't see).
    private func pngData(from pasteboard: NSPasteboard) -> Data? {
      if let png = pasteboard.data(forType: .png) { return png }
      guard let image = NSImage(pasteboard: pasteboard),
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
      else {
        return nil
      }
      return rep.representation(using: .png, properties: [:])
    }

    /// Writes `data` to a uniquely named PNG under a temp subdirectory; returns its
    /// path, or nil if the write fails.
    private func writeTempImage(_ data: Data) -> String? {
      let dir = FileManager.default.temporaryDirectory.appending(
        path: "ProwlQuickSend", directoryHint: .isDirectory)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let url = dir.appending(path: "\(UUID().uuidString).png")
      do {
        try data.write(to: url)
        return url.path
      } catch {
        return nil
      }
    }
  }
}
