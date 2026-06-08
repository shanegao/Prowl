import Foundation
import Testing

@testable import supacode

struct EffectiveCommandsResolverTests {
  @Test func emptyInputsProduceEmptyOutput() {
    let merged = EffectiveCommandsResolver.resolve(globalCommands: [], perRepoCommands: [])
    #expect(merged.isEmpty)
  }

  @Test func globalsOnlyAreReturnedAsIs() {
    let globals = [makeCommand(title: "Build"), makeCommand(title: "Test")]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: [])
    #expect(merged.map(\.title) == ["Build", "Test"])
  }

  @Test func perRepoOnlyAreReturnedAsIs() {
    let perRepo = [makeCommand(title: "Deploy"), makeCommand(title: "Lint")]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: [], perRepoCommands: perRepo)
    #expect(merged.map(\.title) == ["Deploy", "Lint"])
  }

  @Test func unionPlacesGlobalsBeforePerRepo() {
    let globals = [makeCommand(title: "Build"), makeCommand(title: "Test")]
    let perRepo = [makeCommand(title: "Deploy"), makeCommand(title: "Lint")]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: perRepo)
    #expect(merged.map(\.title) == ["Build", "Test", "Deploy", "Lint"])
  }

  @Test func nonConflictingShortcutsArePreservedOnBothLists() {
    let globals = [
      makeCommand(title: "Build", shortcut: shortcut("b"))
    ]
    let perRepo = [
      makeCommand(title: "Deploy", shortcut: shortcut("d"))
    ]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: perRepo)
    #expect(merged[0].shortcut == shortcut("b"))
    #expect(merged[1].shortcut == shortcut("d"))
  }

  @Test func conflictingShortcutClearedOnGlobalNotOnPerRepo() {
    let globals = [
      makeCommand(title: "Global Test", shortcut: shortcut("t"))
    ]
    let perRepo = [
      makeCommand(title: "Repo Test", shortcut: shortcut("t"))
    ]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: perRepo)
    #expect(merged[0].title == "Global Test")
    #expect(merged[0].shortcut == nil, "global command's conflicting shortcut should be cleared")
    #expect(merged[1].title == "Repo Test")
    #expect(merged[1].shortcut == shortcut("t"), "per-repo shortcut survives untouched")
  }

  @Test func globalCommandSurvivesEvenWhenItsShortcutIsCleared() {
    // The global command itself stays in the merged list — only its shortcut is cleared.
    // The user can still invoke it from the toolbar/menu.
    let globals = [
      makeCommand(title: "Global Build", shortcut: shortcut("b"))
    ]
    let perRepo = [
      makeCommand(title: "Repo Build", shortcut: shortcut("b"))
    ]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: perRepo)
    #expect(merged.map(\.title) == ["Global Build", "Repo Build"])
  }

  @Test func conflictDetectionUsesNormalizedShortcuts() {
    // The resolver normalizes shortcuts before comparing, so case differences in `key`
    // shouldn't bypass the conflict rule.
    let globals = [
      makeCommand(title: "Global", shortcut: shortcut("T"))
    ]
    let perRepo = [
      makeCommand(title: "Per-Repo", shortcut: shortcut("t"))
    ]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: perRepo)
    #expect(merged[0].shortcut == nil, "uppercase global vs lowercase per-repo should still conflict")
  }

  @Test func multipleGlobalsWithMixedConflicts() {
    let globals = [
      makeCommand(title: "Build", shortcut: shortcut("b")),
      makeCommand(title: "Test", shortcut: shortcut("t")),
      makeCommand(title: "Lint", shortcut: shortcut("l")),
    ]
    let perRepo = [
      makeCommand(title: "Repo Test", shortcut: shortcut("t"))
    ]
    let merged = EffectiveCommandsResolver.resolve(globalCommands: globals, perRepoCommands: perRepo)
    #expect(merged[0].shortcut == shortcut("b"))
    #expect(merged[1].shortcut == nil)
    #expect(merged[2].shortcut == shortcut("l"))
    #expect(merged[3].shortcut == shortcut("t"))
  }

  // MARK: - Helpers

  private func makeCommand(
    title: String,
    shortcut: UserCustomShortcut? = nil
  ) -> UserCustomCommand {
    UserCustomCommand(
      title: title,
      systemImage: "terminal",
      command: "echo \(title)",
      execution: .shellScript,
      shortcut: shortcut
    )
  }

  private func shortcut(_ key: String) -> UserCustomShortcut {
    UserCustomShortcut(key: key, modifiers: UserCustomShortcutModifiers(command: true))
  }
}
