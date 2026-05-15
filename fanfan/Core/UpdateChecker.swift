//
//  File: UpdateChecker.swift / 文件：UpdateChecker.swift
//  Target: fanfan / 目标：fanfan
//
//  Description: Polls the GitHub Releases API for newer versions. /
//  描述：通过 GitHub Releases API 检查是否有更新版本。
//

import Combine
import Foundation

@MainActor
final class UpdateChecker: ObservableObject {

    struct Release: Equatable {
        let version: String
        let notes: String
        let htmlURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let currentVersion: String
    let currentBuild: String

    init() {
        let bundle = Bundle.main
        self.currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        self.currentBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    private static let releasesAPI = URL(string: "https://api.github.com/repos/hoobnn/fanfan/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/hoobnn/fanfan/releases/latest")!

    /// Reset to `.idle` when the user dismisses an `.available` alert. /
    /// 中文：用户关闭"发现新版本"弹窗时回到 `.idle`，避免下次再次查看仍卡在已读状态。
    func dismissAvailable() {
        if case .available = state { state = .idle }
    }

    func check() async {
        state = .checking
        do {
            var req = URLRequest(url: Self.releasesAPI)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                state = .failed(NSLocalizedString("update.error.network", comment: ""))
                return
            }
            let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = payload.tag_name.hasPrefix("v")
                ? String(payload.tag_name.dropFirst())
                : payload.tag_name
            let pageURL = URL(string: payload.html_url) ?? Self.releasesPage
            if Self.isVersion(latest, newerThan: currentVersion) {
                state = .available(.init(
                    version: latest,
                    notes: payload.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                    htmlURL: pageURL
                ))
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String
    }

    /// Lexicographic semver-ish compare: splits on `.`, ignores non-numeric suffixes. /
    /// 中文：按 `.` 拆分的简易语义化版本比较，忽略非数字后缀。
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let l = lhs.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        let count = max(l.count, r.count)
        for i in 0..<count {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
