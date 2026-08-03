import Foundation
import Combine

@MainActor
final class ThreeEStorageManager: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var isConnected = false
    @Published private(set) var projects: [WebProject] = []
    @Published private(set) var installedWebApps: [InstalledWebApp] = []
    @Published private(set) var isInstallingWebApp = false
    @Published private(set) var catalogEntries: [WebAppCatalogEntry] = []
    @Published private(set) var catalogName: String?
    @Published private(set) var catalogLastCheckedAt: Date?
    @Published private(set) var isLoadingCatalog = false
    @Published var catalogURLString: String
    @Published var allowUnsignedPackages: Bool {
        didSet { UserDefaults.standard.set(allowUnsignedPackages, forKey: unsignedPackagesKey) }
    }
    @Published var operationMessage: String?
    @Published var errorMessage: String?

    let downloadManager = WebAppDownloadManager()

    private let bookmarkKey = "3e.selectedRootFolderBookmark.v1"
    private let catalogURLKey = "3e.webapp.catalogURL.v1"
    private let ignoredVersionsKey = "3e.webapp.ignoredVersions.v1"
    private let unsignedPackagesKey = "3e.webapp.allowUnsignedPackages.v1"
    private let fileManager = FileManager.default
    private var longLivedAccessActive = false
    private var catalogSourceURL: URL?
    private var ignoredUpdateVersions: [String: String]
    private var cancellables = Set<AnyCancellable>()

    init() {
        catalogURLString = UserDefaults.standard.string(forKey: catalogURLKey) ?? ""
        allowUnsignedPackages = UserDefaults.standard.bool(forKey: unsignedPackagesKey)
        ignoredUpdateVersions = UserDefaults.standard.dictionary(forKey: ignoredVersionsKey) as? [String: String] ?? [:]
        downloadManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        restoreSavedFolder()
    }

    var appsURL: URL? { rootURL?.appendingPathComponent("Apps", isDirectory: true) }
    var appFolderURL: URL? { appsURL?.appendingPathComponent(ThreeEAppIdentity.folderName, isDirectory: true) }
    var projectsURL: URL? { appFolderURL?.appendingPathComponent("Projects", isDirectory: true) }
    var installedWebAppsURL: URL? { appFolderURL?.appendingPathComponent("InstalledApps", isDirectory: true) }
    var packagesURL: URL? { appFolderURL?.appendingPathComponent("Packages", isDirectory: true) }
    var signedPackagesURL: URL? { packagesURL?.appendingPathComponent("Signed", isDirectory: true) }
    var signingKeysURL: URL? { appFolderURL?.appendingPathComponent("Keys", isDirectory: true) }
    var signingKeysInboxURL: URL? { signingKeysURL?.appendingPathComponent("Inbox", isDirectory: true) }
    var downloadsURL: URL? { appFolderURL?.appendingPathComponent("Downloads", isDirectory: true) }
    var temporaryWebAppsURL: URL? { appFolderURL?.appendingPathComponent("Cache/WebAppInstaller", isDirectory: true) }
    var sharedURL: URL? { rootURL?.appendingPathComponent("Shared", isDirectory: true) }
    var sharedProjectsURL: URL? { sharedURL?.appendingPathComponent("Projects", isDirectory: true) }
    var systemURL: URL? { rootURL?.appendingPathComponent("System", isDirectory: true) }
    private var pendingImportsURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("PendingWebAppImports", isDirectory: true)
    }

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
            downloadManager.configure(downloadDirectory: downloadsURL)
            isConnected = true
            errorMessage = nil
            refreshAll()
            processPendingWebAppPackages()
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
            downloadManager.configure(downloadDirectory: downloadsURL)
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
            processPendingWebAppPackages()
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
        catalogEntries = []
        catalogName = nil
        catalogSourceURL = nil
        downloadManager.configure(downloadDirectory: nil)
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

    func handleIncomingWebAppPackage(from packageURL: URL) {
        if isConnected {
            installWebAppPackage(from: packageURL)
            return
        }

        let accessed = packageURL.startAccessingSecurityScopedResource()
        defer { if accessed { packageURL.stopAccessingSecurityScopedResource() } }

        do {
            try fileManager.createDirectory(at: pendingImportsURL, withIntermediateDirectories: true)
            let destination = pendingImportsURL.appendingPathComponent(
                "\(UUID().uuidString)-\(packageURL.lastPathComponent)"
            )
            try fileManager.copyItem(at: packageURL, to: destination)
            errorMessage = "تم حفظ حزمة التطبيق مؤقتًا. اختر مجلد 3E وسيتم تثبيتها تلقائيًا."
        } catch {
            errorMessage = "تعذر استقبال حزمة التطبيق: \(error.localizedDescription)"
        }
    }

    private func processPendingWebAppPackages() {
        guard isConnected,
              let files = try? fileManager.contentsOfDirectory(
                at: pendingImportsURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return }

        for file in files where ["3eweb", "zip"].contains(file.pathExtension.lowercased()) {
            installWebAppPackage(from: file)
            try? fileManager.removeItem(at: file)
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
                temporaryRoot: temporaryWebAppsURL,
                allowUnsignedPackages: allowUnsignedPackages
            )
            refreshInstalledWebApps()

            let trustText = outcome.app.isTrustedPackage
                ? " الناشر الموثوق: \(outcome.app.publisherDisplayName ?? "غير معروف")."
                : " الحزمة غير موقعة وتم قبولها عبر وضع المطور."
            switch outcome.kind {
            case .installed:
                operationMessage = "تم تثبيت \(outcome.app.name) بنجاح.\(trustText)"
            case .updated(let previousVersion):
                operationMessage = "تم تحديث \(outcome.app.name) من \(previousVersion) إلى \(outcome.app.version) مع الاحتفاظ بالبيانات.\(trustText)"
            case .reinstalled:
                operationMessage = "تمت إعادة تثبيت \(outcome.app.name) إصدار \(outcome.app.version).\(trustText)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isInstallingWebApp = false
    }

    func addRemoteWebApp(_ draft: RemoteWebAppDraft) {
        guard let installedWebAppsURL else {
            errorMessage = ThreeEStorageError.folderNotConnected.localizedDescription
            return
        }

        isInstallingWebApp = true
        operationMessage = nil
        errorMessage = nil

        do {
            let outcome = try RemoteWebAppInstaller.install(
                draft: draft,
                installedAppsRoot: installedWebAppsURL
            )
            refreshInstalledWebApps()
            switch outcome.kind {
            case .installed:
                operationMessage = "تمت إضافة تطبيق الإنترنت \(outcome.app.name)."
            case .updated:
                operationMessage = "تم تحديث إعدادات تطبيق الإنترنت \(outcome.app.name)."
            case .reinstalled:
                operationMessage = "تم حفظ إعدادات \(outcome.app.name) من جديد."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isInstallingWebApp = false
    }

    @discardableResult
    func markWebAppLaunched(_ app: InstalledWebApp) -> InstalledWebApp {
        do {
            let updated = try RemoteWebAppInstaller.markLaunched(app)
            refreshInstalledWebApps()
            return updated
        } catch {
            return app
        }
    }

    func uninstallWebApp(_ app: InstalledWebApp) {
        do {
            try WebAppPackageInstaller.uninstall(app)
            if app.isRemote {
                WebAppDataStoreIdentifier.removePersistentStore(for: app.id)
            }
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


    func fetchCatalog() async {
        let raw = catalogURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            errorMessage = WebAppCatalogError.invalidURL.localizedDescription
            return
        }

        isLoadingCatalog = true
        errorMessage = nil
        defer { isLoadingCatalog = false }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 45
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                throw WebAppCatalogError.invalidResponse
            }

            let catalog = try JSONDecoder().decode(WebAppCatalog.self, from: data)
            guard catalog.schemaVersion == 1 else {
                throw WebAppCatalogError.unsupportedSchema(catalog.schemaVersion)
            }
            guard catalog.apps.count <= 500 else {
                throw WebAppCatalogError.tooManyApps
            }

            var identifiers = Set<String>()
            let idPattern = "^[A-Za-z0-9][A-Za-z0-9.-]{2,127}$"
            for entry in catalog.apps {
                guard WebAppPackageInstaller.isSafeVersion(entry.version),
                      entry.id.range(of: idPattern, options: .regularExpression) != nil,
                      !entry.id.contains(".."),
                      !entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      identifiers.insert(entry.id).inserted,
                      entry.resolvedPackageURL(relativeTo: url) != nil else {
                    throw WebAppCatalogError.invalidEntry(entry.name)
                }
            }

            catalogEntries = catalog.apps.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            catalogName = catalog.name
            catalogLastCheckedAt = Date()
            catalogSourceURL = url
            catalogURLString = url.absoluteString
            UserDefaults.standard.set(url.absoluteString, forKey: catalogURLKey)
            operationMessage = "تم تحديث فهرس التطبيقات."
        } catch {
            errorMessage = "تعذر تحميل فهرس التطبيقات: \(error.localizedDescription)"
        }
    }

    func catalogEntry(for appID: String) -> WebAppCatalogEntry? {
        catalogEntries.first { $0.id == appID }
    }

    func catalogIconURL(for entry: WebAppCatalogEntry) -> URL? {
        guard let catalogSourceURL else { return nil }
        return entry.resolvedIconURL(relativeTo: catalogSourceURL)
    }

    func availableUpdate(for app: InstalledWebApp) -> WebAppCatalogEntry? {
        guard app.isLocal,
              let entry = catalogEntry(for: app.id),
              entry.isRuntimeCompatible,
              WebAppVersion.compare(entry.version, app.version) == .orderedDescending,
              ignoredUpdateVersions[app.id] != entry.version else {
            return nil
        }
        return entry
    }

    var availableUpdateCount: Int {
        installedWebApps.reduce(into: 0) { count, app in
            if availableUpdate(for: app) != nil { count += 1 }
        }
    }

    func ignoreUpdate(appID: String, version: String) {
        ignoredUpdateVersions[appID] = version
        UserDefaults.standard.set(ignoredUpdateVersions, forKey: ignoredVersionsKey)
        objectWillChange.send()
    }

    func clearIgnoredUpdate(appID: String) {
        ignoredUpdateVersions.removeValue(forKey: appID)
        UserDefaults.standard.set(ignoredUpdateVersions, forKey: ignoredVersionsKey)
        objectWillChange.send()
    }

    func isUpdateIgnored(appID: String, version: String) -> Bool {
        ignoredUpdateVersions[appID] == version
    }

    func downloadCatalogEntry(_ entry: WebAppCatalogEntry) {
        guard let catalogSourceURL,
              let url = entry.resolvedPackageURL(relativeTo: catalogSourceURL) else {
            errorMessage = "رابط حزمة التطبيق غير صالح."
            return
        }
        guard entry.isRuntimeCompatible else {
            errorMessage = "يتطلب هذا التطبيق إصدارًا أحدث من 3ELocal."
            return
        }
        let fileName = "\(entry.id)-\(entry.version).3eweb"
        guard downloadManager.start(
            url: url,
            suggestedName: fileName,
            appID: entry.id,
            version: entry.version
        ) != nil else {
            errorMessage = "تعذر بدء تنزيل التطبيق."
            return
        }
        operationMessage = "بدأ تنزيل \(entry.name). افتح تبويب التنزيلات لمتابعته."
    }

    func downloadPackage(from rawURL: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            errorMessage = "رابط الحزمة غير صالح. يجب استخدام HTTPS."
            return
        }
        guard downloadManager.start(url: url) != nil else {
            errorMessage = "تعذر بدء التنزيل."
            return
        }
        operationMessage = "بدأ تنزيل حزمة التطبيق."
    }

    func installDownloadedPackage(_ item: WebAppDownloadItem) {
        guard let localURL = item.localFileURL else {
            errorMessage = "ملف التنزيل غير متاح."
            return
        }
        downloadManager.markInstalling(item.id)
        installWebAppPackage(from: localURL)
        if errorMessage == nil {
            try? fileManager.removeItem(at: localURL)
            downloadManager.markInstalled(item.id)
            if let appID = item.appID { clearIgnoredUpdate(appID: appID) }
        } else {
            downloadManager.markInstallFailed(item.id, message: errorMessage ?? "تعذر التثبيت.")
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
            "Apps/LocalWeb/Packages/Signed",
            "Apps/LocalWeb/Keys",
            "Apps/LocalWeb/Keys/Inbox",
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
                    "mp3", "mp4", "webm", "zip", "3eweb", "3ekey", "pem"
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
