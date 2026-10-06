import Foundation
import Observation

/// Asks GitHub once a day whether a newer release exists. Nothing is downloaded or installed.
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, page: URL)
        case failed(String)
    }

    private(set) var state = State.idle
    private(set) var lastChecked: Date?
    @ObservationIgnored private var timer: Timer?

    static let latestRelease = URL(
        string: "https://api.github.com/repos/16th-psyche/Comet-42/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/16th-psyche/Comet-42/releases")!

    /// Nil when running outside an app bundle, where there is no version to compare.
    var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func start() {
        Task { await check() }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.check() }
            }
        }
        timer.tolerance = 60 * 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() async {
        guard state != .checking, let current = currentVersion else { return }
        state = .checking
        // Private, cache-less session: the answer is never written to disk.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: Self.latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Comet-42/\(current)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = object["tag_name"] as? String
            else {
                state = .failed("GitHub didn’t return a release.")
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
            state = Self.isVersion(latest, newerThan: current) ? .available(version: latest, page: page) : .upToDate
            lastChecked = Date()
        } catch {
            state = .failed("Couldn’t reach GitHub.")
        }
    }

    /// Numeric, part by part, so 1.10.0 is newer than 1.9.2.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
