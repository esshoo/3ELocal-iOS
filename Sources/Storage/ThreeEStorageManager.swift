import Foundation
import Combine

@MainActor
final class ThreeEStorageManager: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var isConnected = false
    @Published private(set) var projects: [WebProject] = []
    @Published var errorMessage: String?

    private let bookmarkKey = "3e.selectedRootFolderBookmark.v1"
    private let fileManager = FileManager.default
    private var longLivedAccessActive = false

    init() {
        restoreSavedFolder()
    }

    var appsURL: URL? { rootURL?.appendingPathComponent("Apps", isDirectory: true) }
    var appFolderURL: URL? { appsURL?.appendingPathComponent(ThreeEAppIdentity.folderName, isDirectory: true) }
    var projectsURL: URL? { appFolderURL?.appendingPathComponent("Projects", isDirectory: true) }
    var sharedURL: URL? { rootURL?.appendingPathComponent("Shared", isDirectory: true) }
    var sharedProjectsURL: URL? { sharedURL?.appendingPathComponent("Projects", isDirectory: true) }
    var systemURL: URL? { rootURL?.appendingPathComponent("System", isDirectory: true) }

    func connect(to selectedFolderURL: URL) {
        do {
            stopLongLivedAccess()

            guard selectedFolderURL.startAccessingSecurityScopedResource() else {
                throw ThreeEStorageError.accessDenied
            }
            longLivedAccessActive = true
            rootURL = selectedFolderURL

            let bookmark = try selectedFolderURL.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)

            try prepareThreeEStructure(at: selectedFolderURL)
            isConnected = true
            errorMessage = nil
            refreshProjects()
        } catch {
            stopLongLivedAccess()
            rootURL = nil
            isConnected = false
            errorMessage = "Could not connect the 3E folder: \(error.localizedDescription)"
        }
    }

    func restoreSavedFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        do {
            var isStale = false
            let restoredURL = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            guard restoredURL.startAccessingSecurityScopedResource() else {
                throw ThreeEStorageError.accessDenied
            }

            longLivedAccessActive = true
            rootURL = restoredURL
            try prepareThreeEStructure(at: restoredURL)
            isConnected = true

            if isStale {
                let renewed = try restoredURL.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(renewed, forKey: bookmarkKey)
            }

            refreshProjects()
        } catch {
            stopLongLivedAccess()
            rootURL = nil
            isConnected = false
            errorMessage = "Choose the 3E folder again to restore access."
        }
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        stopLongLivedAccess()
        rootURL = nil
        projects = []
        isConnected = false
        errorMessage = nil
    }

    func refreshProjects() {
        guard isConnected else {
            projects = []
            return
        }

        do {
            var discovered: [WebProject] = []
            if let projectsURL {
                discovered.append(contentsOf: try ProjectScanner.scanProjects(in: projectsURL, relativeRoot: "Apps/LocalWeb/Projects"))
            }
            if let sharedProjectsURL {
                discovered.append(contentsOf: try ProjectScanner.scanProjects(in: sharedProjectsURL, relativeRoot: "Shared/Projects"))
            }
            projects = discovered.sorted {
                if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            errorMessage = "Could not scan web projects: \(error.localizedDescription)"
        }
    }

    func createSampleProject() {
        guard let projectsURL else {
            errorMessage = ThreeEStorageError.folderNotConnected.localizedDescription
            return
        }

        let folder = projectsURL.appendingPathComponent("Hello3E", isDirectory: true)
        let index = folder.appendingPathComponent("index.html")
        let style = folder.appendingPathComponent("style.css")
        let script = folder.appendingPathComponent("app.js")

        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: index.path) {
                try Self.sampleHTML.write(to: index, atomically: true, encoding: .utf8)
                try Self.sampleCSS.write(to: style, atomically: true, encoding: .utf8)
                try Self.sampleJS.write(to: script, atomically: true, encoding: .utf8)
            }
            refreshProjects()
        } catch {
            errorMessage = "Could not create the sample project: \(error.localizedDescription)"
        }
    }

    func project(matchingRelativePath path: String) -> WebProject? {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return projects.first {
            $0.relativePath == normalized ||
            normalized.hasPrefix($0.relativePath + "/") ||
            $0.relativePath.hasPrefix(normalized + "/")
        }
    }

    private func stopLongLivedAccess() {
        if longLivedAccessActive {
            rootURL?.stopAccessingSecurityScopedResource()
            longLivedAccessActive = false
        }
    }

    private func prepareThreeEStructure(at root: URL) throws {
        let folders = [
            "Apps",
            "Apps/LiDARLab",
            "Apps/RoomElectrical",
            "Apps/LocalWeb",
            "Apps/LocalWeb/Projects",
            "Apps/LocalWeb/Imports",
            "Apps/LocalWeb/Exports",
            "Apps/LocalWeb/Cache",
            "Apps/LocalWeb/Settings",
            "Shared",
            "Shared/Inbox",
            "Shared/Outbox",
            "Shared/Projects",
            "Shared/Media",
            "System"
        ]

        for relativePath in folders {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(relativePath, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        try updateRegistry(at: root)
    }

    private func updateRegistry(at root: URL) throws {
        let registryURL = root.appendingPathComponent("System/registry.json")
        var rootObject: [String: Any] = [
            "schemaVersion": ThreeEAppIdentity.schemaVersion,
            "apps": [String: Any]()
        ]

        if fileManager.fileExists(atPath: registryURL.path) {
            let data = try Data(contentsOf: registryURL)
            if let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                rootObject = existing
            }
        }

        rootObject["schemaVersion"] = ThreeEAppIdentity.schemaVersion
        var apps = rootObject["apps"] as? [String: Any] ?? [:]
        apps[ThreeEAppIdentity.appKey] = [
            "appKey": ThreeEAppIdentity.appKey,
            "displayName": ThreeEAppIdentity.displayName,
            "bundleIdentifier": ThreeEAppIdentity.bundleIdentifier,
            "urlScheme": ThreeEAppIdentity.urlScheme,
            "folder": ThreeEAppIdentity.relativeFolderPath,
            "supportedExtensions": ["html", "htm", "css", "js", "json", "wasm", "svg", "png", "jpg", "jpeg", "gif", "webp", "mp3", "mp4", "webm", "zip"],
            "lastRegisteredAt": ISO8601DateFormatter().string(from: Date())
        ]
        rootObject["apps"] = apps

        let data = try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: registryURL, options: .atomic)
    }

    private static let sampleHTML = """
    <!doctype html>
    <html lang=\"en\">
    <head>
      <meta charset=\"utf-8\">
      <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
      <title>Hello 3E</title>
      <link rel=\"stylesheet\" href=\"style.css\">
    </head>
    <body>
      <main class=\"card\">
        <div class=\"logo\">3E</div>
        <h1>3ELocal is working</h1>
        <p>This project is served directly from your shared 3E folder.</p>
        <button id=\"test\">Test JavaScript</button>
        <p id=\"result\"></p>
      </main>
      <script src=\"app.js\"></script>
    </body>
    </html>
    """

    private static let sampleCSS = """
    :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: linear-gradient(135deg, #131722, #27354b); }
    .card { width: min(88vw, 620px); padding: 32px; border-radius: 24px; background: rgba(255,255,255,.12); color: white; text-align: center; backdrop-filter: blur(20px); box-shadow: 0 20px 70px rgba(0,0,0,.35); }
    .logo { width: 88px; height: 88px; margin: 0 auto 18px; display: grid; place-items: center; border-radius: 24px; font-weight: 900; font-size: 34px; background: #2e82e6; }
    button { border: 0; border-radius: 14px; padding: 12px 18px; font-weight: 700; font-size: 16px; }
    """

    private static let sampleJS = """
    document.querySelector('#test').addEventListener('click', () => {
      document.querySelector('#result').textContent = `JavaScript works — ${new Date().toLocaleTimeString()}`;
    });
    """
}
