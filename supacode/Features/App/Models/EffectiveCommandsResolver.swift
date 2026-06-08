import Foundation

/// Combines a global command list with a per-repository command list into a single ordered list
/// suitable for the toolbar, menus, and keybinding registration.
///
/// Order: globals first, then per-repo. When a global command's keyboard shortcut collides with
/// any per-repo command's shortcut, the global command's `shortcut` is cleared in the merged
/// output (per-repo wins). The global command itself remains visible in the merged list so the
/// user can still invoke it from the toolbar or menu.
enum EffectiveCommandsResolver {
  static func resolve(
    globalCommands: [UserCustomCommand],
    perRepoCommands: [UserCustomCommand]
  ) -> [UserCustomCommand] {
    let perRepoShortcuts: [UserCustomShortcut] = perRepoCommands.compactMap(\.shortcut).map {
      $0.normalized()
    }
    let resolvedGlobals: [UserCustomCommand] = globalCommands.map { command in
      guard let shortcut = command.shortcut?.normalized(),
        perRepoShortcuts.contains(shortcut)
      else {
        return command
      }
      var withoutShortcut = command
      withoutShortcut.shortcut = nil
      return withoutShortcut
    }
    return resolvedGlobals + perRepoCommands
  }
}
