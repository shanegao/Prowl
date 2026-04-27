import Foundation

struct TerminalTabItem: Identifiable, Equatable, Sendable {
  let id: TerminalTabID
  var title: String
  var icon: String?
  var isDirty: Bool
  var isTitleLocked: Bool
  var isIconLocked: Bool
  /// `true` while a Run Script or Custom Command's configured icon owns
  /// this tab's icon slot. Sits between auto-detected command icons and
  /// `isIconLocked` (user picker) in the precedence chain: blocks
  /// `CommandIconMap`-driven overrides so the play / configured glyph
  /// doesn't get clobbered mid-run, but yields to a user-set lock.
  var isScriptIconActive: Bool

  init(
    id: TerminalTabID = TerminalTabID(),
    title: String,
    icon: String?,
    isDirty: Bool = false,
    isTitleLocked: Bool = false,
    isIconLocked: Bool = false,
    isScriptIconActive: Bool = false
  ) {
    self.id = id
    self.title = title
    self.icon = icon
    self.isDirty = isDirty
    self.isTitleLocked = isTitleLocked
    self.isIconLocked = isIconLocked
    self.isScriptIconActive = isScriptIconActive
  }
}
