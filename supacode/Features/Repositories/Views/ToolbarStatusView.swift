import SwiftUI

struct ToolbarStatusView: View {
  let toast: RepositoriesFeature.StatusToast?
  let pullRequest: GithubPullRequest?
  let codeHost: CodeHost
  /// Whether the selected worktree's repository is a git repo (and thus has a
  /// code host). Gates the no-pull-request fallback button below — shown for any
  /// git repo, not only ones whose remote was recognized as a known host.
  let supportsCodeHost: Bool
  let branchName: String
  let repositoryName: String
  /// Pre-PR branch state for the selected worktree (from `WorktreeInfoEntry`),
  /// surfaced as the no-PR status badge: diff size, commits ahead/behind the base,
  /// and whether the branch is pushed.
  let addedLines: Int?
  let removedLines: Int?
  let aheadCount: Int?
  let behindCount: Int?
  let isPushed: Bool?
  /// Routes a code-host action (open branch / open repo / branch-or-repo) for the
  /// selected worktree; the parent maps it to a `pullRequestAction` send.
  let onCodeHostAction: (RepositoriesFeature.PullRequestAction) -> Void
  /// Opens the diff view for the selected worktree — wired to the same `showDiff`
  /// path the sidebar's change badge uses, so the toolbar's `+/-` badge behaves
  /// like the sidebar's.
  let onShowDiff: () -> Void

  var body: some View {
    Group {
      switch toast {
      case .inProgress(let message):
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
      case .success(let message):
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityHidden(true)
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
      case .warning(let message):
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
          Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .transition(.opacity)
      case nil:
        if let model = PullRequestStatusModel(pullRequest: pullRequest) {
          PullRequestStatusButton(model: model, codeHost: codeHost)
            .transition(.opacity)
        } else if supportsCodeHost {
          CodeHostStatusButton(
            codeHost: codeHost,
            repositoryName: repositoryName,
            branchName: branchName,
            addedLines: addedLines,
            removedLines: removedLines,
            aheadCount: aheadCount,
            behindCount: behindCount,
            isPushed: isPushed,
            onTap: { onCodeHostAction(.openBranchOrRepoOnCodeHost) },
            onShowDiff: onShowDiff,
            onOpenBranch: { onCodeHostAction(.openBranchOnCodeHost) },
            onOpenRepository: { onCodeHostAction(.openOnCodeHost) }
          )
          .transition(.opacity)
        } else {
          MotivationalStatusView()
            .transition(.opacity)
        }
      }
    }
    .animation(.easeInOut(duration: 0.2), value: toast)
    // Floor the center status slot at roughly the clock's footprint so short
    // content (the code-host button or a brief toast) doesn't collapse into a
    // cramped pill — keeps it substantial and centered down to min window width.
    .frame(minWidth: 240)
  }
}

/// Shared text sizes for the no-PR status surfaces. The hover popover
/// (`CodeHostStatusPopover`) is floored at 14pt (`minimum`); the compact toolbar
/// pill (`CodeHostStatusButton`) sits one point smaller at `toolbar`. Fixed sizes
/// keep these predictable where the semantic styles (`.caption`/`.footnote`) render
/// too small.
private enum StatusFontSize {
  static let header: CGFloat = 18
  static let body: CGFloat = 16
  static let minimum: CGFloat = 14
  /// Toolbar status pill text — one point below the popover floor, per design. The
  /// diff badge and the ahead/behind text share this so they read at the same size.
  static let toolbar: CGFloat = 13
}

/// No-pull-request status item for the center toolbar slot. Surfaces the
/// worktree's pre-PR state — diff size, commits ahead/behind the base branch, and
/// push status — as an at-a-glance badge (the inverse of `PullRequestStatusButton`,
/// which shows the same slot once a PR exists). The `+/-` diff badge taps to open
/// the diff view (mirroring the sidebar's change badge); the ahead/behind + push
/// group taps to open the branch page (or the repository if unpushed). Hovering
/// reveals a popover with the full state and explicit Open branch / Open repository
/// actions. Mirrors `PullRequestChecksPopoverButton`'s hover-popover structure.
private struct CodeHostStatusButton: View {
  let codeHost: CodeHost
  let repositoryName: String
  let branchName: String
  let addedLines: Int?
  let removedLines: Int?
  let aheadCount: Int?
  let behindCount: Int?
  let isPushed: Bool?
  let onTap: () -> Void
  let onShowDiff: () -> Void
  let onOpenBranch: () -> Void
  let onOpenRepository: () -> Void

  @State private var isPresented = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  private var diff: (added: Int, removed: Int)? {
    guard let added = addedLines, let removed = removedLines, added != 0 || removed != 0 else { return nil }
    return (added, removed)
  }

  /// Compact "↑ahead ↓behind" for the badge; nil when in sync or unknown.
  private var aheadBehind: String? {
    guard let ahead = aheadCount, let behind = behindCount, ahead != 0 || behind != 0 else { return nil }
    var parts: [String] = []
    if ahead > 0 { parts.append("↑\(ahead)") }
    if behind > 0 { parts.append("↓\(behind)") }
    return parts.joined(separator: " ")
  }

  /// Spoken form of the `↑/↓` badge for VoiceOver — the glyphs alone read poorly.
  private var aheadBehindAccessibilityLabel: String? {
    guard let ahead = aheadCount, let behind = behindCount, ahead != 0 || behind != 0 else { return nil }
    var parts: [String] = []
    if ahead > 0 { parts.append("\(ahead) ahead") }
    if behind > 0 { parts.append("\(behind) behind") }
    return parts.joined(separator: ", ")
  }

  private var hasState: Bool { diff != nil || aheadBehind != nil || isPushed == false }

  var body: some View {
    content
      .font(.system(size: StatusFontSize.toolbar))
      .contentShape(.rect)
      .onHover { hovering in
        isHoveringButton = hovering
        updatePresentation()
      }
      .popover(isPresented: $isPresented) {
        CodeHostStatusPopover(
          codeHost: codeHost,
          repositoryName: repositoryName,
          branchName: branchName,
          diff: diff,
          aheadCount: aheadCount,
          behindCount: behindCount,
          isPushed: isPushed,
          onOpenBranch: onOpenBranch,
          onOpenRepository: onOpenRepository
        )
        .onHover { hovering in
          isHoveringPopover = hovering
          updatePresentation()
        }
        .onDisappear {
          isHoveringPopover = false
          updatePresentation()
        }
      }
      .onDisappear {
        closeTask?.cancel()
      }
  }

  @ViewBuilder private var content: some View {
    if hasState {
      HStack(spacing: 8) {
        if let diff {
          Button(action: onShowDiff) {
            ChangeCountBadge(
              addedLines: diff.added,
              removedLines: diff.removed,
              font: .system(size: StatusFontSize.toolbar)
            )
            // The badge is text + a stroked capsule with no fill, so without an
            // explicit hit shape only the glyphs are clickable — clicks on the
            // padding fall through. Make the whole badge frame the tap target.
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .help(
            AppShortcuts.helpText(
              title: "Show Diff",
              commandID: AppShortcuts.CommandID.showDiff,
              in: resolvedKeybindings
            ))
        }
        if aheadBehind != nil || isPushed == false {
          Button(action: onTap) {
            HStack(spacing: 8) {
              if let aheadBehind {
                Text(aheadBehind)
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
                  .accessibilityLabel(aheadBehindAccessibilityLabel ?? aheadBehind)
              }
              if isPushed == false {
                Image(systemName: "arrow.up.circle")
                  .imageScale(.medium)
                  .foregroundStyle(.orange)
                  .accessibilityLabel("Branch not pushed")
              }
            }
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .help("Open the branch on \(codeHost.displayName), or the repository if unpushed. Hover for details.")
          .accessibilityLabel("Open on \(codeHost.displayName)")
        }
      }
    } else {
      Button(action: onTap) {
        HStack(spacing: 6) {
          Image(systemName: "arrow.triangle.branch").accessibilityHidden(true)
          Text("Open on \(codeHost.displayName)").lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .help("Open the branch on \(codeHost.displayName), or the repository if unpushed. Hover for details.")
      .accessibilityLabel("Open on \(codeHost.displayName)")
    }
  }

  private func updatePresentation() {
    if isHoveringButton || isHoveringPopover {
      closeTask?.cancel()
      isPresented = true
      return
    }
    closeTask?.cancel()
    closeTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: .milliseconds(150))
      if !Task.isCancelled {
        isPresented = false
      }
    }
  }
}

private struct CodeHostStatusPopover: View {
  let codeHost: CodeHost
  let repositoryName: String
  let branchName: String
  let diff: (added: Int, removed: Int)?
  let aheadCount: Int?
  let behindCount: Int?
  let isPushed: Bool?
  let onOpenBranch: () -> Void
  let onOpenRepository: () -> Void

  private var aheadBehindDescription: String? {
    guard let ahead = aheadCount, let behind = behindCount, ahead != 0 || behind != 0 else { return nil }
    var parts: [String] = []
    if ahead > 0 { parts.append("\(ahead) ahead") }
    if behind > 0 { parts.append("\(behind) behind") }
    return parts.joined(separator: " · ")
  }

  private var hasState: Bool { diff != nil || aheadBehindDescription != nil || isPushed != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        if !repositoryName.isEmpty {
          Label(repositoryName, systemImage: "shippingbox")
            .font(.system(size: StatusFontSize.header, weight: .semibold))
            .lineLimit(1)
        }
        if !branchName.isEmpty {
          Label(branchName, systemImage: "arrow.triangle.branch")
            .font(.system(size: StatusFontSize.body))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Text("No pull request yet · \(codeHost.displayName)")
          .font(.system(size: StatusFontSize.minimum))
          .foregroundStyle(.tertiary)
      }
      if hasState {
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          if let diff {
            stateRow(title: "Changes") {
              ChangeCountBadge(
                addedLines: diff.added, removedLines: diff.removed, font: .system(size: StatusFontSize.minimum))
            }
          }
          if let aheadBehindDescription {
            stateRow(title: "Vs base") {
              Text(aheadBehindDescription).font(.system(size: StatusFontSize.body))
            }
          }
          if let isPushed {
            stateRow(title: "Remote") {
              Text(isPushed ? "Pushed to origin" : "Not pushed yet")
                .font(.system(size: StatusFontSize.body))
                .foregroundStyle(isPushed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
          }
        }
      }
      Divider()
      VStack(alignment: .leading, spacing: 2) {
        actionButton(title: "Open branch on \(codeHost.displayName)", action: onOpenBranch)
        actionButton(title: "Open repository on \(codeHost.displayName)", action: onOpenRepository)
      }
    }
    .padding(12)
    .frame(width: 280, alignment: .leading)
  }

  private func stateRow<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.system(size: StatusFontSize.body))
        .foregroundStyle(.secondary)
        .frame(width: 80, alignment: .leading)
      content()
      Spacer(minLength: 0)
    }
  }

  private func actionButton(title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: "arrow.up.forward.square")
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
    .buttonStyle(.plain)
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
