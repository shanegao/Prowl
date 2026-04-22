import SwiftUI

#if DEBUG

  /// DEBUG-only catalogue of the auto-detected tab icons. Each row
  /// renders a `CommandIconMap` entry through the same `TabIconImage`
  /// the actual tab UI uses, so the asset / SF Symbol fallback / size
  /// behaviour shown here matches what users see on a real tab.
  struct IconCatalogView: View {
    var body: some View {
      let entries = CommandIconMap.debugAllEntries
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(entries, id: \.token) { entry in
            IconCatalogRow(token: entry.token, icon: entry.icon)
            Divider().padding(.leading, 60)
          }
        }
        .padding(.horizontal)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private struct IconCatalogRow: View {
    let token: String
    let icon: TabIconSource

    var body: some View {
      HStack(spacing: 16) {
        TabIconImage(rawName: icon.storageString, pointSize: 24)
          .foregroundStyle(.primary)
          .frame(width: 32, height: 32, alignment: .center)
        VStack(alignment: .leading, spacing: 2) {
          Text(token)
            .font(.body.monospaced().weight(.semibold))
          Text(detailLine)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 10)
    }

    private var detailLine: String {
      if let asset = icon.assetName {
        return "asset:\(asset)  ·  fallback sf:\(icon.systemSymbol)"
      }
      return "sf:\(icon.systemSymbol)"
    }
  }

#endif
