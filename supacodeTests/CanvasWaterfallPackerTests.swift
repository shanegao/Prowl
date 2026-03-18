import CoreGraphics
import Testing

@testable import supacode

struct CanvasCardPackerTests {
  private let packer = CanvasCardPacker(spacing: 20, titleBarHeight: 28)

  private func card(_ key: String, width: CGFloat = 800, height: CGFloat = 550) -> CanvasCardPacker.CardInfo {
    CanvasCardPacker.CardInfo(key: key, size: CGSize(width: width, height: height))
  }

  // MARK: - Basic packing

  @Test func singleCardPacks() throws {
    let result = packer.pack(cards: [card("a")], targetRatio: 16.0 / 9.0)

    let layout = try #require(result.layouts["a"])
    #expect(layout.size == CGSize(width: 800, height: 550))
    #expect(result.boundingSize.width > 0)
    #expect(result.boundingSize.height > 0)
  }

  @Test func preservesOriginalCardSizes() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    #expect(result.layouts["a"]?.size == CGSize(width: 600, height: 400))
    #expect(result.layouts["b"]?.size == CGSize(width: 800, height: 300))
  }

  @Test func allCardsArePlaced() {
    let cards = (0..<5).map { card("card\($0)") }
    let result = packer.pack(cards: cards, targetRatio: 16.0 / 9.0)
    #expect(result.layouts.count == 5)
  }

  // MARK: - No overlap

  @Test func cardsDoNotOverlap() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
      card("c", width: 500, height: 500),
      card("d", width: 700, height: 350),
    ]
    let result = packer.pack(cards: cards, targetRatio: 1.5)

    let rects = result.layouts.map { (key, layout) -> CGRect in
      CGRect(
        x: layout.position.x - layout.size.width / 2,
        y: layout.position.y - (layout.size.height + 28) / 2,
        width: layout.size.width,
        height: layout.size.height + 28
      )
    }

    for i in 0..<rects.count {
      for j in (i + 1)..<rects.count {
        // Allow 1pt tolerance for floating point.
        let insetA = rects[i].insetBy(dx: 1, dy: 1)
        let insetB = rects[j].insetBy(dx: 1, dy: 1)
        #expect(!insetA.intersects(insetB), "Cards \(i) and \(j) overlap")
      }
    }
  }

  // MARK: - Aspect ratio targeting

  @Test func resultRatioApproachesTarget() {
    let cards = (0..<6).map { card("card\($0)", width: .random(in: 400...900), height: .random(in: 300...600)) }
    let targetRatio: CGFloat = 16.0 / 9.0
    let result = packer.pack(cards: cards, targetRatio: targetRatio)

    guard result.boundingSize.height > 0 else { return }
    let actualRatio = result.boundingSize.width / result.boundingSize.height
    // Within 2x of target is reasonable for heuristic packing.
    #expect(actualRatio > targetRatio / 2 && actualRatio < targetRatio * 2)
  }

  // MARK: - Edge cases

  @Test func emptyCardsReturnsEmptyResult() {
    let result = packer.pack(cards: [], targetRatio: 1.5)
    #expect(result.layouts.isEmpty)
    #expect(result.boundingSize == .zero)
  }

  @Test func uniformSizeCardsPackTightly() {
    let cards = (0..<4).map { card("card\($0)", width: 600, height: 400) }
    let result = packer.pack(cards: cards, targetRatio: 1.0)

    // For a square target with 4 equal cards, packing should be close to 2x2.
    guard result.boundingSize.height > 0 else { return }
    let area = result.boundingSize.width * result.boundingSize.height
    let cardArea = cards.reduce(0.0) { $0 + ($1.size.width + 20) * ($1.size.height + 28 + 20) }
    // Efficiency should be at least 60% (generous for heuristic packing).
    #expect(cardArea / area > 0.6, "Packing efficiency too low: \(cardArea / area)")
  }

  // MARK: - Spacing

  @Test func cardsHaveMinimumSpacingBetweenThem() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 600, height: 400),
    ]
    let result = packer.pack(cards: cards, targetRatio: 2.0)

    guard let a = result.layouts["a"], let b = result.layouts["b"] else { return }

    // Compute edges (center-based → edge)
    let aRight = a.position.x + a.size.width / 2
    let bLeft = b.position.x - b.size.width / 2
    let aBottom = a.position.y + (a.size.height + 28) / 2
    let bTop = b.position.y - (b.size.height + 28) / 2

    let horizontalGap = bLeft - aRight
    let verticalGap = bTop - aBottom

    // At least one gap direction should be >= spacing (they may be side by side or stacked).
    let hasAdequateSpacing = horizontalGap >= 20 - 1 || verticalGap >= 20 - 1
    #expect(hasAdequateSpacing, "Cards are too close: hGap=\(horizontalGap), vGap=\(verticalGap)")
  }
}
