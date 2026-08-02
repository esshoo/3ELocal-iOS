import Foundation
import UIKit

struct RemoteWebAppMetadata {
    let name: String?
    let appDescription: String?
    let startURL: URL
    let iconData: Data?
    let manifestURL: URL?
}

enum RemoteWebAppMetadataFetcher {
    private static let maximumHTMLBytes = 5 * 1_024 * 1_024
    private static let maximumIconBytes = 8 * 1_024 * 1_024

    static func fetch(from inputURL: URL) async throws -> RemoteWebAppMetadata {
        let pageURL = try normalizedHTTPSURL(inputURL)
        let (pageData, response) = try await URLSession.shared.data(from: pageURL)
        try validateHTTPResponse(response, dataCount: pageData.count, maximumBytes: maximumHTMLBytes)

        let html = String(data: pageData, encoding: .utf8)
            ?? String(data: pageData, encoding: .isoLatin1)
            ?? ""

        let manifestURL = linkURL(relContaining: "manifest", html: html, baseURL: pageURL)
        var manifest: WebsiteManifest?
        if let manifestURL {
            manifest = try? await fetchManifest(at: manifestURL)
        }

        let suggestedName = manifest?.name
            ?? manifest?.shortName
            ?? metaContent(keys: ["application-name", "apple-mobile-web-app-title", "og:site_name"], html: html)
            ?? htmlTitle(html)

        let description = manifest?.appDescription
            ?? metaContent(keys: ["description", "og:description"], html: html)

        let manifestStartURL = manifest?.startURL.flatMap { URL(string: $0, relativeTo: manifestURL ?? pageURL)?.absoluteURL }
        let startURL = (manifestStartURL?.scheme?.lowercased() == "https") ? manifestStartURL! : pageURL

        var iconCandidates: [URL] = []
        if let manifest, let manifestURL {
            iconCandidates.append(contentsOf: manifest.icons
                .sorted { $0.score > $1.score }
                .compactMap { URL(string: $0.src, relativeTo: manifestURL)?.absoluteURL })
        }
        iconCandidates.append(contentsOf: linkURLs(
            relValues: ["apple-touch-icon", "icon", "shortcut icon"],
            html: html,
            baseURL: pageURL
        ))
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL {
            iconCandidates.append(fallback)
        }

        var iconData: Data?
        for candidate in uniqueURLs(iconCandidates) {
            if let data = try? await fetchIcon(at: candidate) {
                iconData = data
                break
            }
        }

        return RemoteWebAppMetadata(
            name: clean(suggestedName),
            appDescription: clean(description),
            startURL: startURL,
            iconData: iconData,
            manifestURL: manifestURL
        )
    }

    static func normalizedHTTPSURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https", url.host != nil else {
            throw WebAppPackageError.invalidRemoteURL(url.absoluteString)
        }
        return url
    }

    private static func fetchManifest(at url: URL) async throws -> WebsiteManifest {
        guard url.scheme?.lowercased() == "https" else {
            throw WebAppPackageError.invalidRemoteURL(url.absoluteString)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, dataCount: data.count, maximumBytes: 1 * 1_024 * 1_024)
        return try JSONDecoder().decode(WebsiteManifest.self, from: data)
    }

    private static func fetchIcon(at url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw WebAppPackageError.invalidRemoteURL(url.absoluteString)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, dataCount: data.count, maximumBytes: maximumIconBytes)
        guard let image = UIImage(data: data), let png = image.pngData() else {
            throw WebAppPackageError.invalidIcon(url.absoluteString)
        }
        return png
    }

    private static func validateHTTPResponse(
        _ response: URLResponse,
        dataCount: Int,
        maximumBytes: Int
    ) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard dataCount <= maximumBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
    }

    private static func htmlTitle(_ html: String) -> String? {
        firstCapture(pattern: "<title[^>]*>(.*?)</title>", text: html)
            .map(decodeHTMLEntities)
    }

    private static func metaContent(keys: [String], html: String) -> String? {
        let tags = allMatches(pattern: "<meta\\s+[^>]*>", text: html)
        for tag in tags {
            let attributes = parseAttributes(tag)
            let key = (attributes["name"] ?? attributes["property"] ?? "").lowercased()
            if keys.contains(where: { $0.lowercased() == key }), let content = attributes["content"] {
                return decodeHTMLEntities(content)
            }
        }
        return nil
    }

    private static func linkURL(relContaining value: String, html: String, baseURL: URL) -> URL? {
        linkURLs(relValues: [value], html: html, baseURL: baseURL).first
    }

    private static func linkURLs(relValues: [String], html: String, baseURL: URL) -> [URL] {
        let tags = allMatches(pattern: "<link\\s+[^>]*>", text: html)
        return tags.compactMap { tag in
            let attributes = parseAttributes(tag)
            let rel = (attributes["rel"] ?? "").lowercased()
            guard relValues.contains(where: { rel.contains($0.lowercased()) }),
                  let href = attributes["href"],
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  url.scheme?.lowercased() == "https" else {
                return nil
            }
            return url
        }
    }

    private static func parseAttributes(_ tag: String) -> [String: String] {
        let pattern = "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*=\\s*([\\\"'])(.*?)\\2"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: range) where match.numberOfRanges >= 4 {
            guard let keyRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag) else { continue }
            result[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }
        return result
    }

    private static func allMatches(pattern: String, text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func firstCapture(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[capture])
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        guard let data = value.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            return value
        }
        return attributed.string
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private struct WebsiteManifest: Decodable {
        let name: String?
        let shortName: String?
        let appDescription: String?
        let startURL: String?
        let icons: [WebsiteIcon]

        enum CodingKeys: String, CodingKey {
            case name
            case shortName = "short_name"
            case appDescription = "description"
            case startURL = "start_url"
            case icons
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            shortName = try container.decodeIfPresent(String.self, forKey: .shortName)
            appDescription = try container.decodeIfPresent(String.self, forKey: .appDescription)
            startURL = try container.decodeIfPresent(String.self, forKey: .startURL)
            icons = try container.decodeIfPresent([WebsiteIcon].self, forKey: .icons) ?? []
        }
    }

    private struct WebsiteIcon: Decodable {
        let src: String
        let sizes: String?
        let type: String?

        var score: Int {
            let dimensions = (sizes ?? "")
                .split(separator: " ")
                .compactMap { token -> Int? in
                    let side = token.lowercased().split(separator: "x").first
                    return side.flatMap { Int($0) }
                }
            return dimensions.max() ?? (type?.contains("svg") == true ? 1024 : 0)
        }
    }
}
