import Foundation
import Combine
import Network
import Darwin

final class LocalHTTPServer: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(message: String)
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var localURL: URL?
    @Published private(set) var networkURL: URL?

    private let queue = DispatchQueue(label: "com.essam.3E.localweb.httpserver", qos: .userInitiated)
    private var listener: NWListener?
    private var rootURL: URL?
    private var initialRelativePath = "index.html"

    func start(projectRoot: URL, indexURL: URL, preferredPort: UInt16? = nil) {
        stop()

        rootURL = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        initialRelativePath = relativePath(from: projectRoot, to: indexURL) ?? "index.html"
        publish { self.state = .starting }

        do {
            let endpointPort: NWEndpoint.Port
            if let preferredPort, let requestedPort = NWEndpoint.Port(rawValue: preferredPort) {
                endpointPort = requestedPort
            } else {
                endpointPort = .any
            }
            let listener = try NWListener(using: .tcp, on: endpointPort)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                switch newState {
                case .ready:
                    guard let port = listener.port?.rawValue else { return }
                    let encodedPath = self.initialRelativePath
                        .split(separator: "/")
                        .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                        .joined(separator: "/")
                    let local = URL(string: "http://127.0.0.1:\(port)/\(encodedPath)")
                    let network = Self.wifiIPv4Address().flatMap {
                        URL(string: "http://\($0):\(port)/\(encodedPath)")
                    }
                    self.publish {
                        self.localURL = local
                        self.networkURL = network
                        self.state = .running(port: port)
                    }

                case .failed(let error):
                    self.publish {
                        self.state = .failed(message: error.localizedDescription)
                        self.localURL = nil
                        self.networkURL = nil
                    }
                    listener.cancel()

                case .cancelled:
                    self.publish {
                        self.state = .stopped
                        self.localURL = nil
                        self.networkURL = nil
                    }

                default:
                    break
                }
            }

            listener.start(queue: queue)
        } catch {
            publish {
                self.state = .failed(message: error.localizedDescription)
                self.localURL = nil
                self.networkURL = nil
            }
        }
    }


    static func stablePort(for identifier: String) -> UInt16 {
        var hash: UInt32 = 2_166_136_261
        for byte in identifier.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return UInt16(20_000 + (hash % 25_000))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        rootURL = nil
        publish {
            self.state = .stopped
            self.localURL = nil
            self.networkURL = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receiveRequest(on: connection, accumulated: Data())
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: buffer, on: connection)
            } else if isComplete || error != nil || buffer.count >= 64 * 1024 {
                self.send(status: 400, reason: "Bad Request", headers: [:], body: Data(), on: connection)
            } else {
                self.receiveRequest(on: connection, accumulated: buffer)
            }
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        guard let requestText = String(data: requestData, encoding: .utf8) else {
            send(status: 400, reason: "Bad Request", headers: [:], body: Data(), on: connection)
            return
        }

        let lines = requestText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            send(status: 400, reason: "Bad Request", headers: [:], body: Data(), on: connection)
            return
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            send(status: 400, reason: "Bad Request", headers: [:], body: Data(), on: connection)
            return
        }

        let method = String(requestParts[0]).uppercased()
        guard method == "GET" || method == "HEAD" else {
            send(status: 405, reason: "Method Not Allowed", headers: ["Allow": "GET, HEAD"], body: Data(), on: connection)
            return
        }

        let rawTarget = String(requestParts[1])
        let headers = parseHeaders(Array(lines.dropFirst()))

        guard let fileURL = resolveFileURL(from: rawTarget) else {
            send(status: 404, reason: "Not Found", headers: [:], body: Data("404 Not Found".utf8), on: connection)
            return
        }

        do {
            let fullData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let mime = Self.mimeType(for: fileURL.pathExtension)
            var responseHeaders = [
                "Content-Type": mime,
                "Accept-Ranges": "bytes",
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ]

            var status = 200
            var reason = "OK"
            var body = fullData

            if let rangeHeader = headers["range"],
               let range = byteRange(from: rangeHeader, totalCount: fullData.count) {
                status = 206
                reason = "Partial Content"
                body = fullData.subdata(in: range)
                responseHeaders["Content-Range"] = "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(fullData.count)"
            }

            if method == "HEAD" { body = Data() }
            send(status: status, reason: reason, headers: responseHeaders, body: body, declaredLength: method == "HEAD" ? fullData.count : nil, on: connection)
        } catch {
            send(status: 500, reason: "Internal Server Error", headers: [:], body: Data(error.localizedDescription.utf8), on: connection)
        }
    }

    private func resolveFileURL(from rawTarget: String) -> URL? {
        guard let rootURL else { return nil }
        let pathWithoutQuery = rawTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let decoded = pathWithoutQuery.removingPercentEncoding ?? pathWithoutQuery
        let relative = decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requested = relative.isEmpty ? initialRelativePath : relative

        guard PathSafety.safeRelativePath(requested) != nil else { return nil }

        var candidate = rootURL.appendingPathComponent(requested).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == rootURL.path || candidate.path.hasPrefix(rootURL.path + "/") else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            candidate.appendPathComponent("index.html")
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func parseHeaders(_ lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        return headers
    }

    private func byteRange(from header: String, totalCount: Int) -> Range<Int>? {
        guard totalCount > 0, header.lowercased().hasPrefix("bytes=") else { return nil }
        let value = header.dropFirst(6).split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        if parts[0].isEmpty, let suffixCount = Int(parts[1]), suffixCount > 0 {
            let start = max(totalCount - suffixCount, 0)
            return start..<totalCount
        }

        guard let start = Int(parts[0]), start >= 0, start < totalCount else { return nil }
        let endInclusive = Int(parts[1]) ?? (totalCount - 1)
        let endExclusive = min(max(endInclusive + 1, start + 1), totalCount)
        return start..<endExclusive
    }

    private func send(
        status: Int,
        reason: String,
        headers: [String: String],
        body: Data,
        declaredLength: Int? = nil,
        on connection: NWConnection
    ) {
        var responseHeaders = headers
        responseHeaders["Content-Length"] = String(declaredLength ?? body.count)
        responseHeaders["Connection"] = "close"

        var headerText = "HTTP/1.1 \(status) \(reason)\r\n"
        for key in responseHeaders.keys.sorted() {
            if let value = responseHeaders[key] {
                headerText += "\(key): \(value)\r\n"
            }
        }
        headerText += "\r\n"

        var response = Data(headerText.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func relativePath(from root: URL, to child: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.starts(with: rootComponents) else { return nil }
        return childComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func publish(_ update: @escaping () -> Void) {
        DispatchQueue.main.async(execute: update)
    }

    private static func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json", "map", "webmanifest": return "application/json; charset=utf-8"
        case "wasm": return "application/wasm"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "ogg": return "audio/ogg"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain; charset=utf-8"
        case "xml": return "application/xml; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    private static func wifiIPv4Address() -> String? {
        var address: String?
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                address = String(cString: host)
                break
            }
        }
        return address
    }
}
