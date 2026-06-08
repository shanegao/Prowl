import ComposableArchitecture

struct GithubIntegrationClient: Sendable {
  var isAvailable: @MainActor @Sendable () async -> Bool
}

private actor GithubIntegrationAvailabilityCache {
  private struct Entry {
    let value: Bool
    let fetchedAt: ContinuousClock.Instant
  }

  private let ttl: Duration
  private let clock = ContinuousClock()
  private var cachedEntry: Entry?

  init(ttl: Duration) {
    self.ttl = ttl
  }

  func value(orFetch fetch: @Sendable @escaping () async -> Bool) async -> Bool {
    let now = clock.now
    if let cachedEntry,
      cachedEntry.fetchedAt.duration(to: now) < ttl
    {
      return cachedEntry.value
    }

    // Fetch directly on the actor — no detached `Task`. The actor already
    // serializes access; storing this escaping closure in an unstructured
    // `Task` over-released its captured `GithubCLIClient` on task completion,
    // a heap-corrupting double-free that crashed the app at launch (the crash
    // signature varied run-to-run, the hallmark of free-list corruption).
    let value = await fetch()
    cachedEntry = Entry(value: value, fetchedAt: clock.now)
    return value
  }

  func clear() {
    cachedEntry = nil
  }
}

private let githubIntegrationAvailabilityCache = GithubIntegrationAvailabilityCache(
  ttl: .seconds(30)
)

extension GithubIntegrationClient: DependencyKey {
  static let liveValue = GithubIntegrationClient(
    isAvailable: {
      await githubIntegrationIsAvailable()
    }
  )
  static let testValue = GithubIntegrationClient(
    isAvailable: { true }
  )
}

extension DependencyValues {
  var githubIntegration: GithubIntegrationClient {
    get { self[GithubIntegrationClient.self] }
    set { self[GithubIntegrationClient.self] = newValue }
  }
}

@MainActor
private func githubIntegrationIsAvailable() async -> Bool {
  @Shared(.settingsFile) var settingsFile
  @Dependency(GithubCLIClient.self) var githubCLI
  guard settingsFile.global.githubIntegrationEnabled else {
    await githubIntegrationAvailabilityCache.clear()
    return false
  }
  // Capture a concrete resolved closure, not the `@Dependency`-wrapped
  // `GithubCLIClient` struct (per `~/.claude/rules/ios.md`: no `@Dependency`
  // inside escaping closures).
  let isAvailable = githubCLI.isAvailable
  return await githubIntegrationAvailabilityCache.value {
    await isAvailable()
  }
}
