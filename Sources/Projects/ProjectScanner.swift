import Foundation

enum ProjectScanner {
    static func scanProjects(in root: URL, relativeRoot: String) throws -> [WebProject] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )

        var projects: [WebProject] = []
        for child in children {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            guard values.isDirectory == true, values.isHidden != true else { continue }
            guard let indexURL = findIndex(in: child, maxDepth: 3) else { continue }

            let stats = directoryStats(at: child)
            let modifiedAt = (try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let relativePath = relativeRoot + "/" + child.lastPathComponent

            projects.append(
                WebProject(
                    id: relativePath,
                    name: child.lastPathComponent,
                    relativePath: relativePath,
                    directoryURL: child,
                    indexURL: indexURL,
                    modifiedAt: modifiedAt,
                    fileCount: stats.count,
                    totalBytes: stats.bytes
                )
            )
        }

        return projects
    }

    private static func findIndex(in directory: URL, maxDepth: Int) -> URL? {
        let fileManager = FileManager.default
        let directCandidates = ["index.html", "index.htm"]
        for candidate in directCandidates {
            let url = directory.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) { return url }
        }

        guard maxDepth > 0,
              let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { return nil }

        for case let url as URL in enumerator {
            let relativeComponents = url.pathComponents.dropFirst(directory.pathComponents.count)
            if relativeComponents.count > maxDepth + 1 {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent.lowercased() == "index.html" || url.lastPathComponent.lowercased() == "index.htm" {
                return url
            }

            if url.lastPathComponent == "node_modules" || url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
            }
        }
        return nil
    }

    private static func directoryStats(at directory: URL) -> (count: Int, bytes: Int64) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return (0, 0) }

        var count = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            if url.lastPathComponent == "node_modules" || url.lastPathComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (count, bytes)
    }
}
