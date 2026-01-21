import Foundation
import AppKit

class UpdateChecker: ObservableObject {
    @Published var newVersionAvailable = false
    @Published var latestVersion = ""
    @Published var downloadURL = ""
    @Published var releaseNotes = ""

    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    private let githubRepo = "calebyhan/smart-charge"

    func checkForUpdates() async {
        guard let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            if isNewerVersion(release.tagName) {
                await MainActor.run {
                    self.newVersionAvailable = true
                    self.latestVersion = release.tagName
                    self.releaseNotes = release.body
                    // Find .pkg asset, fallback to release page
                    if let pkgAsset = release.assets.first(where: { $0.name.hasSuffix(".pkg") }) {
                        self.downloadURL = pkgAsset.browserDownloadURL
                    } else {
                        self.downloadURL = release.htmlURL
                    }
                }
            }
        } catch {
            // Silently fail - don't bother user with update check errors
            print("Update check failed: \(error)")
        }
    }

    private func isNewerVersion(_ tagName: String) -> Bool {
        let newVersion = tagName.replacingOccurrences(of: "v", with: "")
        return newVersion.compare(currentVersion, options: .numeric) == .orderedDescending
    }

    func openDownloadPage() {
        if let url = URL(string: downloadURL) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - GitHub API Models

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlURL: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }

    struct Asset: Codable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
