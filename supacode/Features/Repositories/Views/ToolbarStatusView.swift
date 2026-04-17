import SwiftUI

struct ToolbarStatusView: View {
  let toast: RepositoriesFeature.StatusToast?
  let pullRequest: GithubPullRequest?

  private static let transition: AnyTransition = .asymmetric(
    insertion: .opacity.combined(with: .offset(y: -4)),
    removal: .opacity.combined(with: .offset(y: 4))
  )

  var body: some View {
    ZStack {
      content
        .id(identityKey)
        .transition(Self.transition)
    }
    .animation(.easeInOut(duration: 0.28), value: identityKey)
  }

  @ViewBuilder
  private var content: some View {
    switch toast {
    case .inProgress(let message):
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.small)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    case .success(let message):
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityHidden(true)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    case .warning(let message):
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
          .accessibilityHidden(true)
        Text(message)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    case nil:
      if let model = PullRequestStatusModel(pullRequest: pullRequest) {
        PullRequestStatusButton(model: model)
      } else {
        MotivationalStatusView()
      }
    }
  }

  // Derive a stable per-content identity so SwiftUI can transition not only when
  // the toast kind toggles but also when the message text changes between two
  // consecutive successes / warnings.
  private var identityKey: String {
    switch toast {
    case .inProgress(let message):
      return "progress:\(message)"
    case .success(let message):
      return "success:\(message)"
    case .warning(let message):
      return "warning:\(message)"
    case nil:
      if let number = pullRequest?.number {
        return "pr:\(number)"
      }
      return "idle"
    }
  }
}

private struct MotivationalStatusView: View {
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    TimelineView(.everyMinute) { context in
      let hour = Calendar.current.component(.hour, from: context.date)
      let style = timeStyle(for: hour)
      let commandPaletteHint = AppShortcuts.helpText(
        title: "Open Command Palette",
        commandID: AppShortcuts.CommandID.commandPalette,
        in: resolvedKeybindings
      )
      HStack(spacing: 8) {
        Image(systemName: style.icon)
          .foregroundStyle(style.color)
          .font(.callout)
          .accessibilityHidden(true)
        Text("\(context.date, format: .dateTime.hour().minute()) – \(commandPaletteHint)")
          .font(.footnote)
          .monospaced()
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct TimeStyle {
  let icon: String
  let color: Color
}

private func timeStyle(for hour: Int) -> TimeStyle {
  switch hour {
  case 6..<12:
    TimeStyle(icon: "sunrise.fill", color: .orange)
  case 12..<17:
    TimeStyle(icon: "sun.max.fill", color: .yellow)
  case 17..<21:
    TimeStyle(icon: "sunset.fill", color: .pink)
  default:
    TimeStyle(icon: "moon.stars.fill", color: .indigo)
  }
}
