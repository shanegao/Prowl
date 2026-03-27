import CustomDump
import SwiftUI
import Testing

@testable import supacode

@MainActor
struct AppShortcutsTests {
  @Test func displaySymbolsMatchDisplay() {
    let shortcuts: [AppShortcut] = [
      AppShortcuts.openSettings,
      AppShortcuts.newWorktree,
      AppShortcuts.copyPath,
    ]

    for shortcut in shortcuts {
      expectNoDifference(shortcut.displaySymbols.joined(), shortcut.display)
    }
  }

  @Test func worktreeSelectionUsesControlNumberShortcuts() {
    expectNoDifference(
      AppShortcuts.worktreeSelection.map(\.display),
      ["⌃1", "⌃2", "⌃3", "⌃4", "⌃5", "⌃6", "⌃7", "⌃8", "⌃9", "⌃0"]
    )

    for shortcut in AppShortcuts.worktreeSelection {
      #expect(shortcut.modifiers == .control)
    }
  }

  @Test func defaultGlobalShortcutTableMatchesPlan() {
    expectNoDifference(
      [
        "openSettings=\(AppShortcuts.openSettings.display)",
        "toggleLeftSidebar=\(AppShortcuts.toggleLeftSidebar.display)",
        "runScript=\(AppShortcuts.runScript.display)",
        "stopRunScript=\(AppShortcuts.stopRunScript.display)",
        "checkForUpdates=\(AppShortcuts.checkForUpdates.display)",
        "showDiff=\(AppShortcuts.showDiff.display)",
        "openFinder=\(AppShortcuts.openFinder.display)",
        "openRepository=\(AppShortcuts.openRepository.display)",
      ],
      [
        "openSettings=⌘,",
        "toggleLeftSidebar=⌘B",
        "runScript=⌘R",
        "stopRunScript=⌘⇧R",
        "checkForUpdates=⌘⇧,",
        "showDiff=⌘⇧]",
        "openFinder=⌘O",
        "openRepository=⌘⇧O",
      ]
    )
  }

  @Test func customCommandConflictDetectionMatchesReservedList() {
    for reserved in AppShortcuts.reservedCustomCommandShortcuts {
      let customShortcut = OnevcatCustomShortcut(
        key: reserved.key,
        modifiers: OnevcatCustomShortcutModifiers(
          command: reserved.modifiers.contains(.command),
          shift: reserved.modifiers.contains(.shift),
          option: reserved.modifiers.contains(.option),
          control: reserved.modifiers.contains(.control)
        )
      )

      let conflict = AppShortcuts.customCommandConflict(for: customShortcut)
      #expect(conflict == reserved)
    }

    #expect(
      AppShortcuts.customCommandConflict(
        for: OnevcatCustomShortcut(
          key: "k",
          modifiers: OnevcatCustomShortcutModifiers(command: true)
        )
      ) == nil
    )
  }

  @Test func tabSelectionGhosttyKeybindArgumentsMatchExpected() {
    expectNoDifference(
      AppShortcuts.tabSelectionGhosttyKeybindArguments,
      [
        "--keybind=ctrl+1=goto_tab:1",
        "--keybind=ctrl+digit_1=goto_tab:1",
        "--keybind=ctrl+2=goto_tab:2",
        "--keybind=ctrl+digit_2=goto_tab:2",
        "--keybind=ctrl+3=goto_tab:3",
        "--keybind=ctrl+digit_3=goto_tab:3",
        "--keybind=ctrl+4=goto_tab:4",
        "--keybind=ctrl+digit_4=goto_tab:4",
        "--keybind=ctrl+5=goto_tab:5",
        "--keybind=ctrl+digit_5=goto_tab:5",
        "--keybind=ctrl+6=goto_tab:6",
        "--keybind=ctrl+digit_6=goto_tab:6",
        "--keybind=ctrl+7=goto_tab:7",
        "--keybind=ctrl+digit_7=goto_tab:7",
        "--keybind=ctrl+8=goto_tab:8",
        "--keybind=ctrl+digit_8=goto_tab:8",
        "--keybind=ctrl+9=goto_tab:9",
        "--keybind=ctrl+digit_9=goto_tab:9",
        "--keybind=ctrl+0=goto_tab:10",
        "--keybind=ctrl+digit_0=goto_tab:10",
      ]
    )
  }

  @Test func ghosttyCLIArgumentsKeepWorktreeUnbindsAndTabBinds() {
    let arguments = AppShortcuts.ghosttyCLIKeybindArguments

    for shortcut in AppShortcuts.worktreeSelection {
      #expect(arguments.contains(shortcut.ghosttyUnbindArgument))
    }

    for argument in AppShortcuts.tabSelectionGhosttyKeybindArguments {
      #expect(arguments.contains(argument))
    }

    for argument in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"].map({ "--keybind=ctrl+digit_\($0)=unbind" }) {
      #expect(arguments.contains(argument) == false)
    }
  }
}
