import Testing

@testable import supacode

struct EffectiveCustomCommandTests {
  @Test func localCommandsKeepOrderAndHideMatchingGlobalTitles() {
    let localBuild = command(id: "local-build", title: " Build ")
    let localTest = command(id: "local-test", title: "Test")
    let hiddenGlobalBuild = command(id: "global-build", title: "build")
    let globalLint = command(id: "global-lint", title: "Lint")

    let resolved = EffectiveCustomCommand.resolve(
      repositoryCommands: [localBuild, localTest],
      globalCommands: [hiddenGlobalBuild, globalLint]
    )

    #expect(
      resolved.map(\.id) == [
        .init(source: .repository, commandID: "local-build"),
        .init(source: .repository, commandID: "local-test"),
        .init(source: .global, commandID: "global-lint"),
      ])
  }

  @Test func sourceQualifiedIdentityPreventsLocalGlobalUUIDCollisions() {
    let local = EffectiveCustomCommand(source: .repository, command: command(id: "same", title: "Local"))
    let global = EffectiveCustomCommand(source: .global, command: command(id: "same", title: "Global"))

    #expect(local.id != global.id)
    #expect(local.keybindingID == "custom_command.same")
    #expect(global.keybindingID == "custom_command.global.same")
    #expect(local.paletteID == "custom-command.same")
    #expect(global.paletteID == "custom-command.global.same")
  }

  private func command(id: String, title: String) -> UserCustomCommand {
    UserCustomCommand(
      id: id,
      title: title,
      systemImage: "terminal",
      command: "echo \(title)",
      execution: .shellScript,
      shortcut: nil
    )
  }
}
