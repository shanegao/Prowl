import ComposableArchitecture
import SwiftUI

struct ActiveAgentsPanel: View {
  @Bindable var store: StoreOf<ActiveAgentsFeature>
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
        Text("No active agents")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(store.entries) { entry in
              Button {
                store.send(.entryTapped(entry.id))
              } label: {
                ActiveAgentRow(entry: entry)
              }
              .buttonStyle(.plain)
              .help("Focus \(entry.agent.displayName) in \(entry.worktreeName)")
            }
          }
        }
        .scrollIndicators(.never)
      }
    }
    .background(.bar)
    .overlay(alignment: .top) {
      Divider()
    }
  }

  private var resizeHandle: some View {
    Rectangle()
      .fill(.separator)
      .frame(height: 1)
      .frame(maxWidth: .infinity)
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
}
