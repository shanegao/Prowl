import ComposableArchitecture
import SwiftUI

struct ActiveAgentsPanel: View {
  @Bindable var store: StoreOf<ActiveAgentsFeature>
  let repositoryNamesByWorktreeID: [Worktree.ID: String]
  let branchNamesByWorktreeID: [Worktree.ID: String]
  let repositoryColorsByWorktreeID: [Worktree.ID: RepositoryColorChoice]
  let selectedSurfaceID: UUID?
  let height: Double
  let maximumHeight: Double
  let onHeightChanged: (Double) -> Void
  let onHeightChangeEnded: (Double) -> Void
  @State private var dragStartHeight: Double?

  var body: some View {
    VStack(spacing: 0) {
      resizeHandle
      HStack {
        Text("Active Agents")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 4)

      if store.entries.isEmpty {
        Spacer(minLength: 0)
        Text("New agents will appear here")
          .font(.callout)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(store.entries) { entry in
              Button {
                store.send(.entryTapped(entry.id))
              } label: {
                ActiveAgentRow(
                  entry: entry,
                  repositoryName: repositoryName(for: entry),
                  branchName: branchName(for: entry),
                  repositoryColor: repositoryColor(for: entry),
                  isDimmed: isDimmed(entry)
                )
              }
              .buttonStyle(.plain)
              .help("Focus \(entry.agent.displayName) in \(repositoryName(for: entry))")
            }
          }
        }
        .scrollIndicators(.never)
      }
    }
    .background {
      panelBackgroundShape
        .fill(.thinMaterial)
    }
    .clipShape(panelBackgroundShape)
    .overlay {
      panelBackgroundShape
        .stroke(.separator.opacity(0.7), lineWidth: 1)
    }
  }

  private var resizeHandle: some View {
    Rectangle()
      .fill(.clear)
      .frame(height: 1)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(.separator.opacity(0.7))
          .frame(height: 1)
          .padding(.horizontal, 8)
      }
      .overlay {
        Rectangle()
          .fill(.clear)
          .frame(height: 8)
          .contentShape(.rect)
      }
      .gesture(
        DragGesture(coordinateSpace: .global)
          .onChanged { value in
            let start = dragStartHeight ?? height
            dragStartHeight = start
            onHeightChanged(clampedHeight(start - value.translation.height))
          }
          .onEnded { value in
            let start = dragStartHeight ?? height
            let height = clampedHeight(start - value.translation.height)
            dragStartHeight = nil
            onHeightChangeEnded(height)
          }
      )
      .onHover { hovering in
        if hovering {
          NSCursor.resizeUpDown.set()
        } else {
          NSCursor.arrow.set()
        }
      }
  }

  private func clampedHeight(_ height: Double) -> Double {
    min(maximumHeight, max(ActiveAgentsFeature.minimumPanelHeight, height))
  }

  private func repositoryName(for entry: ActiveAgentEntry) -> String {
    repositoryNamesByWorktreeID[entry.worktreeID] ?? entry.worktreeName
  }

  private func branchName(for entry: ActiveAgentEntry) -> String {
    branchNamesByWorktreeID[entry.worktreeID] ?? entry.worktreeName
  }

  private func repositoryColor(for entry: ActiveAgentEntry) -> RepositoryColorChoice? {
    repositoryColorsByWorktreeID[entry.worktreeID]
  }

  private func isDimmed(_ entry: ActiveAgentEntry) -> Bool {
    if let selectedSurfaceID {
      return entry.surfaceID != selectedSurfaceID
    }
    return false
  }

  private var panelBackgroundShape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      cornerRadii: .init(
        topLeading: 8,
        bottomLeading: 0,
        bottomTrailing: 0,
        topTrailing: 8
      ),
      style: .continuous
    )
  }
}
