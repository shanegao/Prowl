import ComposableArchitecture
import SwiftUI

struct ActiveAgentsPanel: View {
  @Bindable var store: StoreOf<ActiveAgentsFeature>
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
        DragGesture()
          .onChanged { value in
            let start = dragStartHeight ?? store.panelHeight
            dragStartHeight = start
            store.send(.panelHeightChanged(start - value.translation.height))
          }
          .onEnded { _ in
            dragStartHeight = nil
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
}
