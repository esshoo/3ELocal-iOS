import Foundation
import Combine

struct WebAppDownloadItem: Identifiable, Hashable {
    enum State: String, Hashable {
        case queued
        case downloading
        case paused
        case downloaded
        case installing
        case installed
        case failed
        case cancelled
    }

    let id: UUID
    let sourceURL: URL
    let appID: String?
    let version: String?
    var displayName: String
    var progress: Double
    var state: State
    var receivedBytes: Int64
    var expectedBytes: Int64
    var localFileURL: URL?
    var errorMessage: String?

    var canPause: Bool { state == .downloading }
    var canResume: Bool { state == .paused }
    var canRetry: Bool { state == .failed || state == .cancelled }
    var canInstall: Bool { state == .downloaded && localFileURL != nil }
}

final class WebAppDownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [WebAppDownloadItem] = []

    private var downloadDirectory: URL?
    private var tasksByID: [UUID: URLSessionDownloadTask] = [:]
    private var idsByTaskIdentifier: [Int: UUID] = [:]
    private var resumeDataByID: [UUID: Data] = [:]
    private var preferredFileNames: [UUID: String] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    func configure(downloadDirectory: URL?) {
        self.downloadDirectory = downloadDirectory
        guard let downloadDirectory else {
            tasksByID.values.forEach { $0.cancel() }
            tasksByID.removeAll()
            idsByTaskIdentifier.removeAll()
            resumeDataByID.removeAll()
            items = []
            return
        }
        try? FileManager.default.createDirectory(
            at: downloadDirectory,
            withIntermediateDirectories: true
        )
        restoreDownloadedFiles(in: downloadDirectory)
    }

    @discardableResult
    func start(
        url: URL,
        suggestedName: String? = nil,
        appID: String? = nil,
        version: String? = nil
    ) -> UUID? {
        guard url.scheme?.lowercased() == "https", url.host != nil else { return nil }

        let id = UUID()
        let name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name! : url.lastPathComponent)
        let item = WebAppDownloadItem(
            id: id,
            sourceURL: url,
            appID: appID,
            version: version,
            displayName: displayName.isEmpty ? "تطبيق 3E Web" : displayName,
            progress: 0,
            state: .queued,
            receivedBytes: 0,
            expectedBytes: 0,
            localFileURL: nil,
            errorMessage: nil
        )
        items.insert(item, at: 0)
        preferredFileNames[id] = preferredPackageFileName(
            suggestedName: suggestedName,
            url: url,
            appID: appID,
            version: version
        )
        createTask(for: id, request: URLRequest(url: url))
        return id
    }

    func pause(_ id: UUID) {
        guard let task = tasksByID[id] else { return }
        update(id) { $0.state = .paused }
        task.cancel(byProducingResumeData: { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data { self.resumeDataByID[id] = data }
                self.removeTaskReferences(id: id, taskIdentifier: task.taskIdentifier)
            }
        })
    }

    func resume(_ id: UUID) {
        guard let data = resumeDataByID.removeValue(forKey: id) else {
            retry(id)
            return
        }
        let task = session.downloadTask(withResumeData: data)
        register(task: task, for: id)
        update(id) {
            $0.state = .downloading
            $0.errorMessage = nil
        }
        task.resume()
    }

    func retry(_ id: UUID) {
        guard let item = item(withID: id) else { return }
        if let local = item.localFileURL { try? FileManager.default.removeItem(at: local) }
        update(id) {
            $0.progress = 0
            $0.receivedBytes = 0
            $0.expectedBytes = 0
            $0.localFileURL = nil
            $0.errorMessage = nil
            $0.state = .queued
        }
        createTask(for: id, request: URLRequest(url: item.sourceURL))
    }

    func cancel(_ id: UUID) {
        if let task = tasksByID[id] {
            task.cancel()
            removeTaskReferences(id: id, taskIdentifier: task.taskIdentifier)
        }
        resumeDataByID.removeValue(forKey: id)
        update(id) { $0.state = .cancelled }
    }

    func remove(_ id: UUID) {
        cancel(id)
        if let local = item(withID: id)?.localFileURL {
            try? FileManager.default.removeItem(at: local)
        }
        items.removeAll { $0.id == id }
        preferredFileNames.removeValue(forKey: id)
    }

    func clearFinished() {
        let removable = items.filter {
            [.installed, .failed, .cancelled].contains($0.state)
        }
        for item in removable { remove(item.id) }
    }

    func markInstalling(_ id: UUID) {
        update(id) { $0.state = .installing }
    }

    func markInstalled(_ id: UUID) {
        update(id) {
            $0.state = .installed
            $0.localFileURL = nil
        }
    }

    func markInstallFailed(_ id: UUID, message: String) {
        update(id) {
            $0.state = .downloaded
            $0.errorMessage = message
        }
    }

    func item(withID id: UUID) -> WebAppDownloadItem? {
        items.first { $0.id == id }
    }

    private func restoreDownloadedFiles(in directory: URL) {
        let activeURLs = Set(items.compactMap(\.localFileURL))
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let restored = files.compactMap { file -> WebAppDownloadItem? in
            guard !activeURLs.contains(file),
                  ["3eweb", "zip"].contains(file.pathExtension.lowercased()),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return WebAppDownloadItem(
                id: UUID(),
                sourceURL: file,
                appID: nil,
                version: nil,
                displayName: file.lastPathComponent,
                progress: 1,
                state: .downloaded,
                receivedBytes: size,
                expectedBytes: size,
                localFileURL: file,
                errorMessage: nil
            )
        }
        items.append(contentsOf: restored)
    }

    private func createTask(for id: UUID, request: URLRequest) {
        let task = session.downloadTask(with: request)
        register(task: task, for: id)
        update(id) { $0.state = .downloading }
        task.resume()
    }

    private func register(task: URLSessionDownloadTask, for id: UUID) {
        tasksByID[id] = task
        idsByTaskIdentifier[task.taskIdentifier] = id
    }

    private func removeTaskReferences(id: UUID, taskIdentifier: Int) {
        tasksByID.removeValue(forKey: id)
        idsByTaskIdentifier.removeValue(forKey: taskIdentifier)
    }

    private func update(_ id: UUID, mutate: (inout WebAppDownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func preferredPackageFileName(
        suggestedName: String?,
        url: URL,
        appID: String?,
        version: String?
    ) -> String {
        var value = suggestedName ?? url.lastPathComponent
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = [appID, version].compactMap { $0 }.joined(separator: "-")
        }
        if value.isEmpty { value = "WebApp-\(UUID().uuidString)" }
        value = value.replacingOccurrences(of: "/", with: "-")
        value = value.replacingOccurrences(of: "\\", with: "-")
        if !["3eweb", "zip"].contains(URL(fileURLWithPath: value).pathExtension.lowercased()) {
            value += ".3eweb"
        }
        return value
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let fm = FileManager.default
        let initial = directory.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: initial.path) else { return initial }
        let source = URL(fileURLWithPath: fileName)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        for number in 2...999 {
            let candidate = directory.appendingPathComponent("\(base)-\(number).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(UUID().uuidString).3eweb")
    }
}

extension WebAppDownloadManager: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = idsByTaskIdentifier[downloadTask.taskIdentifier] else { return }
        update(id) {
            $0.receivedBytes = totalBytesWritten
            $0.expectedBytes = max(0, totalBytesExpectedToWrite)
            $0.progress = totalBytesExpectedToWrite > 0
                ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
                : 0
            $0.state = .downloading
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = idsByTaskIdentifier[downloadTask.taskIdentifier],
              let directory = downloadDirectory else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let responseName = downloadTask.response?.suggestedFilename
            let preferred = preferredFileNames[id]
                ?? preferredPackageFileName(
                    suggestedName: responseName,
                    url: downloadTask.originalRequest?.url ?? location,
                    appID: item(withID: id)?.appID,
                    version: item(withID: id)?.version
                )
            let destination = uniqueDestination(in: directory, fileName: preferred)
            try FileManager.default.moveItem(at: location, to: destination)
            update(id) {
                $0.localFileURL = destination
                $0.progress = 1
                $0.state = .downloaded
                $0.errorMessage = nil
            }
        } catch {
            update(id) {
                $0.state = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let id = idsByTaskIdentifier[task.taskIdentifier] else { return }
        defer { removeTaskReferences(id: id, taskIdentifier: task.taskIdentifier) }
        guard let error = error as NSError? else { return }
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return
        }
        update(id) {
            $0.state = .failed
            $0.errorMessage = error.localizedDescription
        }
    }
}
