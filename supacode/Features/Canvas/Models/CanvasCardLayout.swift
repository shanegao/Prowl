import CoreGraphics
import Foundation

struct CanvasCardLayout: Codable, Equatable, Hashable, Sendable {
  var positionX: CGFloat
  var positionY: CGFloat
  var width: CGFloat
  var height: CGFloat

  var position: CGPoint {
    get { CGPoint(x: positionX, y: positionY) }
    set {
      positionX = newValue.x
      positionY = newValue.y
    }
  }

  var size: CGSize {
    get { CGSize(width: width, height: height) }
    set {
      width = newValue.width
      height = newValue.height
    }
  }

  static let defaultSize = CGSize(width: 800, height: 550)

  init(position: CGPoint, size: CGSize = Self.defaultSize) {
    self.positionX = position.x
    self.positionY = position.y
    self.width = size.width
    self.height = size.height
  }
}

// MARK: - Card Packing

struct CanvasCardPacker {
  var spacing: CGFloat
  var titleBarHeight: CGFloat

  struct CardInfo {
    var key: String
    var size: CGSize
  }

  struct PackResult {
    var layouts: [String: CanvasCardLayout]
    var boundingSize: CGSize
  }

  /// Pack cards into a rectangle whose aspect ratio best matches `targetRatio`.
  ///
  /// Uses MaxRects-BSSF (Best Short Side Fit) internally. A binary search over
  /// bin widths finds the width that produces a bounding box closest to the
  /// desired aspect ratio.
  func pack(cards: [CardInfo], targetRatio: CGFloat) -> PackResult {
    guard !cards.isEmpty, targetRatio > 0 else {
      return PackResult(layouts: [:], boundingSize: .zero)
    }

    // Pad each card with spacing on all sides so the packer handles gaps.
    let paddedCards = cards.map { card in
      CGSize(
        width: card.size.width + spacing,
        height: card.size.height + titleBarHeight + spacing
      )
    }

    // Sort by area descending — large items first gives better packing.
    let sortedIndices = paddedCards.indices.sorted {
      paddedCards[$0].width * paddedCards[$0].height >
        paddedCards[$1].width * paddedCards[$1].height
    }

    let maxW = paddedCards.map(\.width).max()!
    let totalArea = paddedCards.reduce(0.0) { $0 + $1.width * $1.height }

    // Binary search for the bin width that best matches targetRatio.
    var lo = maxW + spacing
    var hi = max(lo, sqrt(totalArea * targetRatio) * 3)
    var bestResult: (positions: [(CGFloat, CGFloat)], w: CGFloat, h: CGFloat)?
    var bestDiff = CGFloat.infinity

    for _ in 0..<20 {
      let mid = (lo + hi) / 2
      let binW = mid + spacing  // extra spacing for left margin
      if let positions = maxRectsPack(sizes: paddedCards, order: sortedIndices, binWidth: binW) {
        let (bw, bh) = boundingBox(positions: positions, sizes: paddedCards)
        let ratio = bw / bh
        let diff = abs(ratio - targetRatio)
        if diff < bestDiff {
          bestDiff = diff
          bestResult = (positions, bw, bh)
        }
        if ratio > targetRatio {
          hi = mid
        } else {
          lo = mid
        }
      } else {
        // Couldn't fit — bin too narrow.
        lo = mid
      }
    }

    // Fallback: very wide bin (single row).
    if bestResult == nil {
      let fallbackW = paddedCards.reduce(spacing) { $0 + $1.width } + spacing
      if let positions = maxRectsPack(sizes: paddedCards, order: sortedIndices, binWidth: fallbackW) {
        let (bw, bh) = boundingBox(positions: positions, sizes: paddedCards)
        bestResult = (positions, bw, bh)
      }
    }

    guard let result = bestResult else {
      return PackResult(layouts: [:], boundingSize: .zero)
    }

    // Convert padded positions back to center-based CanvasCardLayout.
    var layouts: [String: CanvasCardLayout] = [:]
    for (i, card) in cards.enumerated() {
      let (px, py) = result.positions[i]
      // px, py is top-left of padded rect; card center = padded origin + spacing/2 + cardSize/2
      let centerX = px + spacing / 2 + card.size.width / 2
      let centerY = py + spacing / 2 + (card.size.height + titleBarHeight) / 2
      layouts[card.key] = CanvasCardLayout(
        position: CGPoint(x: centerX, y: centerY),
        size: card.size
      )
    }

    return PackResult(layouts: layouts, boundingSize: CGSize(width: result.w, height: result.h))
  }

  // MARK: - MaxRects-BSSF

  /// Place rectangles into a strip of fixed width and unlimited height.
  /// Returns top-left positions in the original `sizes` order, or nil if any
  /// rect is wider than `binWidth`.
  private func maxRectsPack(
    sizes: [CGSize],
    order: [Int],
    binWidth: CGFloat
  ) -> [(CGFloat, CGFloat)]? {
    // Generous height — we only care about the actual used extent.
    let binHeight: CGFloat = sizes.reduce(0) { $0 + $1.height } + spacing
    var freeRects = [CGRect(x: spacing, y: spacing, width: binWidth - spacing, height: binHeight)]
    var positions = Array(repeating: (CGFloat(0), CGFloat(0)), count: sizes.count)

    for idx in order {
      let size = sizes[idx]
      guard size.width <= binWidth else { return nil }

      // BSSF: find free rect where the shorter leftover side is minimized.
      var bestRect = CGRect.null
      var bestShortSide = CGFloat.infinity
      var bestLongSide = CGFloat.infinity

      for freeRect in freeRects {
        guard size.width <= freeRect.width && size.height <= freeRect.height else { continue }
        let leftoverW = freeRect.width - size.width
        let leftoverH = freeRect.height - size.height
        let shortSide = min(leftoverW, leftoverH)
        let longSide = max(leftoverW, leftoverH)
        if shortSide < bestShortSide || (shortSide == bestShortSide && longSide < bestLongSide) {
          bestRect = freeRect
          bestShortSide = shortSide
          bestLongSide = longSide
        }
      }

      guard !bestRect.isNull else { return nil }

      let placed = CGRect(x: bestRect.minX, y: bestRect.minY, width: size.width, height: size.height)
      positions[idx] = (placed.minX, placed.minY)

      // Split free rects intersecting with the placed rect.
      var newFreeRects: [CGRect] = []
      for freeRect in freeRects {
        guard freeRect.intersects(placed) else {
          newFreeRects.append(freeRect)
          continue
        }
        // Left remainder
        if placed.minX > freeRect.minX {
          newFreeRects.append(CGRect(
            x: freeRect.minX, y: freeRect.minY,
            width: placed.minX - freeRect.minX, height: freeRect.height
          ))
        }
        // Right remainder
        if placed.maxX < freeRect.maxX {
          newFreeRects.append(CGRect(
            x: placed.maxX, y: freeRect.minY,
            width: freeRect.maxX - placed.maxX, height: freeRect.height
          ))
        }
        // Top remainder
        if placed.minY > freeRect.minY {
          newFreeRects.append(CGRect(
            x: freeRect.minX, y: freeRect.minY,
            width: freeRect.width, height: placed.minY - freeRect.minY
          ))
        }
        // Bottom remainder
        if placed.maxY < freeRect.maxY {
          newFreeRects.append(CGRect(
            x: freeRect.minX, y: placed.maxY,
            width: freeRect.width, height: freeRect.maxY - placed.maxY
          ))
        }
      }

      // Prune: remove any free rect fully contained within another.
      freeRects = pruneContained(newFreeRects)
    }

    return positions
  }

  /// Remove rectangles that are fully contained within another rectangle.
  private func pruneContained(_ rects: [CGRect]) -> [CGRect] {
    var result: [CGRect] = []
    for (i, a) in rects.enumerated() {
      var contained = false
      for (j, b) in rects.enumerated() where i != j {
        if b.contains(a) {
          contained = true
          break
        }
      }
      if !contained {
        result.append(a)
      }
    }
    return result
  }

  /// Compute the bounding box of all placed padded rects.
  private func boundingBox(
    positions: [(CGFloat, CGFloat)],
    sizes: [CGSize]
  ) -> (width: CGFloat, height: CGFloat) {
    var maxX: CGFloat = 0
    var maxY: CGFloat = 0
    for (i, (px, py)) in positions.enumerated() {
      maxX = max(maxX, px + sizes[i].width)
      maxY = max(maxY, py + sizes[i].height)
    }
    return (maxX + spacing, maxY + spacing)
  }
}

@MainActor
@Observable
final class CanvasLayoutStore {
  private static let storageKey = "canvasCardLayouts"

  var cardLayouts: [String: CanvasCardLayout] {
    didSet { save() }
  }

  init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
      let layouts = try? JSONDecoder().decode([String: CanvasCardLayout].self, from: data)
    {
      self.cardLayouts = layouts
    } else {
      self.cardLayouts = [:]
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(cardLayouts) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }
}
