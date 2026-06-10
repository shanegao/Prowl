import SwiftUI

struct WorkspaceRepositoriesGridView: View {
  let workspace: ProjectWorkspace
  let rootURL: URL

  var body: some View {
    if workspace.repositories.isEmpty {
      Text("No repositories are declared in this workspace metadata.")
        .font(.callout)
        .foregroundStyle(.secondary)
    } else {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
        GridRow {
          header("Name")
          header("Role")
          header("Source")
          header("Branch")
          header("Path")
        }
        Divider()
          .gridCellUnsizedAxes(.horizontal)
        ForEach(workspace.repositories) { entry in
          GridRow(alignment: .firstTextBaseline) {
            Text(entry.name)
              .font(.subheadline.weight(.medium))
            Text(entry.role ?? " ")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Text(sourceKindTitle(entry.sourceKind))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .help(entry.sourceLocation ?? "")
            Text(entry.branchName ?? entry.baseRef ?? " ")
              .font(.subheadline.monospaced())
              .foregroundStyle(.secondary)
            Text(entry.resolvedURL(relativeTo: rootURL).path(percentEncoded: false))
              .font(.subheadline.monospaced())
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
              .textSelection(.enabled)
          }
        }
      }
    }
  }

  private func header(_ title: String) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.tertiary)
  }

  private func sourceKindTitle(_ kind: ProjectWorkspaceRepositorySourceKind) -> String {
    switch kind {
    case .existingPath:
      return "Linked"
    case .localRepository:
      return "Local"
    case .remote:
      return "Remote"
    case .bareRepository:
      return "Bare"
    }
  }
}
