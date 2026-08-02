import Foundation
import Combine

@MainActor
final class ThreeEStorageManager: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var isConnected = false
    @Published private(set) var projects: [WebProject] = []
    @Published private(set) var installedWebApps: [InstalledWebApp] = []
    @Published private(set) var isInstallingWebApp = false
    @Published var operationMessage: String?
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
    var installedWebAppsURL: URL? { appFolderURL?.appendingPathComponent("InstalledApps", isDirectory: true) }
    var packagesURL: URL? { appFolderURL?.appendingPathComponent("Packages", isDirectory: true) }
    var downloadsURL: URL? { appFolderURL?.appendingPathComponent("Downloads", isDirectory: true) }
    var temporaryWebAppsURL: URL? { appFolderURL?.appendingPathComponent("Cache/WebAppInstaller", isDirectory: true) }
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
            refreshAll()
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

            refreshAll()
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
        installedWebApps = []
        isConnected = false
        errorMessage = nil
    }

    func refreshAll() {
        refreshProjects()
        refreshInstalledWebApps()
    }

    func refreshInstalledWebApps() {
        guard isConnected, let installedWebAppsURL else {
            installedWebApps = []
            return
        }

        do {
            installedWebApps = try WebAppPackageInstaller.scanInstalledApps(in: installedWebAppsURL)
        } catch {
            errorMessage = "تعذر قراءة التطبيقات المثبتة: \(error.localizedDescription)"
        }
    }

    func installWebAppPackage(from packageURL: URL) {
        guard let installedWebAppsURL, let temporaryWebAppsURL else {
            errorMessage = ThreeEStorageError.folderNotConnected.localizedDescription
            return
        }

        isInstallingWebApp = true
        operationMessage = nil
        errorMessage = nil

        do {
            let outcome = try WebAppPackageInstaller.install(
                packageURL: packageURL,
                installedAppsRoot: installedWebAppsURL,
                temporaryRoot: temporaryWebAppsURL
            )
            refreshInstalledWebApps()

            switch outcome.kind {
            case .installed:
                operationMessage = "تم تثبيت \(outcome.app.name) بنجاح."
            case .updated(let previousVersion):
                operationMessage = "تم تحديث \(outcome.app.name) من \(previousVersion) إلى \(outcome.app.version) مع الاحتفاظ بالبيانات."
            case .reinstalled:
                operationMessage = "تمت إعادة تثبيت \(outcome.app.name) إصدار \(outcome.app.version)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isInstallingWebApp = false
    }

    func uninstallWebApp(_ app: InstalledWebApp) {
        do {
            try WebAppPackageInstaller.uninstall(app)
            refreshInstalledWebApps()
            operationMessage = "تم حذف \(app.name) وبياناته المحلية."
        } catch {
            errorMessage = "تعذر حذف التطبيق: \(error.localizedDescription)"
        }
    }

    func rollbackWebApp(_ app: InstalledWebApp) {
        do {
            let rolledBack = try WebAppPackageInstaller.rollback(app)
            refreshInstalledWebApps()
            operationMessage = "تم الرجوع بـ \(rolledBack.name) إلى الإصدار \(rolledBack.version)."
        } catch {
            errorMessage = "تعذر الرجوع إلى الإصدار السابق: \(error.localizedDescription)"
        }
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
            "Apps/LocalWeb/InstalledApps",
            "Apps/LocalWeb/Packages",
            "Apps/LocalWeb/Downloads",
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
        let systemURL = root.appendingPathComponent("System", isDirectory: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?

        coordinator.coordinate(
            writingItemAt: systemURL,
            options: [],
            error: &coordinationError
        ) { coordinatedSystemURL in
            do {
                let registryURL = coordinatedSystemURL
                    .appendingPathComponent("registry.json")
                var rootObject: [String: Any]

                if fileManager.fileExists(atPath: registryURL.path) {
                    let data = try Data(contentsOf: registryURL)
                    let json = try JSONSerialization.jsonObject(with: data)
                    guard let existing = json as? [String: Any] else {
                        throw ThreeEStorageError.invalidRegistryRoot
                    }
                    rootObject = existing
                } else {
                    rootObject = [
                        "schemaVersion": ThreeEAppIdentity.schemaVersion,
                        "apps": [String: Any]()
                    ]
                }

                rootObject["schemaVersion"] = ThreeEAppIdentity.schemaVersion
                var apps = try Self.normalizedRegistryApps(
                    from: rootObject["apps"]
                )
                let appKey = ThreeEAppIdentity.appKey
                var localEntry = apps[appKey] ?? [:]

                localEntry["appKey"] = appKey
                localEntry["displayName"] = ThreeEAppIdentity.displayName
                localEntry["bundleIdentifier"] = ThreeEAppIdentity.bundleIdentifier
                localEntry["urlScheme"] = ThreeEAppIdentity.urlScheme
                localEntry["folder"] = ThreeEAppIdentity.relativeFolderPath
                localEntry["supportedExtensions"] = [
                    "html", "htm", "css", "js", "json", "wasm",
                    "svg", "png", "jpg", "jpeg", "gif", "webp",
                    "mp3", "mp4", "webm", "zip", "3eweb"
                ]
                localEntry["lastRegisteredAt"] = ISO8601DateFormatter()
                    .string(from: Date())

                apps[appKey] = localEntry
                rootObject["apps"] = apps

                let data = try JSONSerialization.data(
                    withJSONObject: rootObject,
                    options: [
                        .prettyPrinted,
                        .sortedKeys,
                        .withoutEscapingSlashes
                    ]
                )
                try data.write(to: registryURL, options: .atomic)
            } catch {
                operationError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let operationError {
            throw operationError
        }
    }

    /// Supports both the original array form and the canonical dictionary
    /// form used by the 3E suite. The next write always uses the dictionary.
    private static func normalizedRegistryApps(
        from rawValue: Any?
    ) throws -> [String: [String: Any]] {
        guard let rawValue else {
            return [:]
        }

        if let dictionary = rawValue as? [String: Any] {
            var result: [String: [String: Any]] = [:]

            for (dictionaryKey, rawEntry) in dictionary {
                guard var entry = rawEntry as? [String: Any] else {
                    throw ThreeEStorageError.invalidRegistryApps
                }

                let storedKey = (entry["appKey"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let appKey = (storedKey?.isEmpty == false)
                    ? storedKey!
                    : dictionaryKey
                entry["appKey"] = appKey
                result[appKey] = entry
            }

            return result
        }

        if let array = rawValue as? [[String: Any]] {
            var result: [String: [String: Any]] = [:]

            for entry in array {
                guard let appKey = (entry["appKey"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !appKey.isEmpty else {
                    throw ThreeEStorageError.invalidRegistryApps
                }
                result[appKey] = entry
            }

            return result
        }

        throw ThreeEStorageError.invalidRegistryApps
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
