//
//  GlobalCommandsFeatureTests.swift
//  supacode
//
//  Created by Shane Gao on 2026-06-26.
//

import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct GlobalCommandsFeatureTests {

  // MARK: - mergeByID (pure function)

  @Test func mergeByIDWithDisjointIDsUnionsExistingFirst() {
    let existing = [
      makeCommand(id: "1", title: "Build"),
      makeCommand(id: "2", title: "Test"),
    ]
    let imported = [
      makeCommand(id: "3", title: "Deploy"),
      makeCommand(id: "4", title: "Lint"),
    ]

    let merged = GlobalCommandsFeature.mergeByID(existing: existing, imported: imported)

    // Disjoint ids → full union, existing entries kept ahead of imported (result starts as `existing`).
    #expect(merged.map(\.id) == ["1", "2", "3", "4"])
    #expect(merged.map(\.title) == ["Build", "Test", "Deploy", "Lint"])
  }

  @Test func mergeByIDDropsImportedCommandWithDuplicateIDAndKeepsExisting() {
    // Same id, but the imported copy has a different title/command — proving which side wins.
    let existing = [makeCommand(id: "1", title: "Build", command: "make")]
    let imported = [makeCommand(id: "1", title: "Renamed Build", command: "bazel build")]

    let merged = GlobalCommandsFeature.mergeByID(existing: existing, imported: imported)

    // Dedupe is by id: the imported duplicate is dropped entirely, the existing command survives untouched.
    #expect(merged.count == 1)
    #expect(merged[0].title == "Build")
    #expect(merged[0].command == "make")
  }

  @Test func mergeByIDClearsImportedShortcutThatCollidesWithExisting() {
    // Distinct ids (so the imported command is appended), but both bind ⌘B.
    let existing = [makeCommand(id: "1", title: "Build", shortcut: shortcut("b"))]
    let imported = [makeCommand(id: "2", title: "Repo Build", shortcut: shortcut("b"))]

    let merged = GlobalCommandsFeature.mergeByID(existing: existing, imported: imported)

    // Collision rule: keep the imported command, lose its key. The existing side is never touched.
    #expect(merged.count == 2)
    #expect(merged[0].title == "Build")
    #expect(merged[0].shortcut == shortcut("b"), "existing command keeps its shortcut")
    #expect(merged[1].title == "Repo Build")
    #expect(merged[1].shortcut == nil, "imported colliding shortcut should be cleared")
  }

  @Test func mergeByIDPreservesNonCollidingImportedShortcut() {
    let existing = [makeCommand(id: "1", title: "Build", shortcut: shortcut("b"))]
    let imported = [makeCommand(id: "2", title: "Deploy", shortcut: shortcut("d"))]

    let merged = GlobalCommandsFeature.mergeByID(existing: existing, imported: imported)

    // No collision → both keys survive.
    #expect(merged[0].shortcut == shortcut("b"))
    #expect(merged[1].shortcut == shortcut("d"))
  }

  // MARK: - importCompleted (reducer action via TestStore)

  @Test func importCompletedMergesAndEmitsCommandsChanged() async {
    let existing = makeCommand(id: "1", title: "Build", command: "make")
    let store = TestStore(initialState: GlobalCommandsFeature.State(commands: [existing])) {
      GlobalCommandsFeature()
    }

    // Imported set: a duplicate id (dropped) + a brand-new command (appended).
    let duplicate = makeCommand(id: "1", title: "Renamed Build", command: "bazel build")
    let fresh = makeCommand(id: "2", title: "Deploy")

    await store.send(.importCompleted([duplicate, fresh])) {
      $0.commands = [existing, fresh]
    }
    await store.receive(\.delegate.commandsChanged)
  }

  @Test func importCompletedClearsCollidingImportedShortcut() async {
    let existing = makeCommand(id: "1", title: "Build", shortcut: shortcut("b"))
    let store = TestStore(initialState: GlobalCommandsFeature.State(commands: [existing])) {
      GlobalCommandsFeature()
    }

    let importedColliding = makeCommand(id: "2", title: "Repo Build", shortcut: shortcut("b"))
    var importedSanitized = importedColliding
    importedSanitized.shortcut = nil

    await store.send(.importCompleted([importedColliding])) {
      // Existing command keeps ⌘B; imported command is appended with its shortcut cleared.
      $0.commands = [existing, importedSanitized]
    }
    await store.receive(\.delegate.commandsChanged)
  }

  // MARK: - Helpers

  private func makeCommand(
    id: String,
    title: String,
    command: String = "echo run",
    shortcut: UserCustomShortcut? = nil
  ) -> UserCustomCommand {
    UserCustomCommand(
      id: id,
      title: title,
      systemImage: "terminal",
      command: command,
      execution: .shellScript,
      shortcut: shortcut
    )
  }

  private func shortcut(_ key: String) -> UserCustomShortcut {
    UserCustomShortcut(key: key, modifiers: UserCustomShortcutModifiers(command: true))
  }
}
