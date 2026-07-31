import Foundation
import Combine

@MainActor
final class ProjectLibraryStore: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String>
    @Published private(set) var recentIDs: [String]

    private let favoritesKey = "3e.localweb.favorites.v1"
    private let recentsKey = "3e.localweb.recents.v1"
    private let maxRecents = 20

    init() {
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        recentIDs = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    func isFavorite(_ project: WebProject) -> Bool {
        favoriteIDs.contains(project.id)
    }

    func toggleFavorite(_ project: WebProject) {
        if favoriteIDs.contains(project.id) {
            favoriteIDs.remove(project.id)
        } else {
            favoriteIDs.insert(project.id)
        }
        saveFavorites()
    }

    func markOpened(_ project: WebProject) {
        recentIDs.removeAll(where: { $0 == project.id })
        recentIDs.insert(project.id, at: 0)
        recentIDs = Array(recentIDs.prefix(maxRecents))
        UserDefaults.standard.set(recentIDs, forKey: recentsKey)
    }

    func recentRank(for project: WebProject) -> Int? {
        recentIDs.firstIndex(of: project.id)
    }

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs).sorted(), forKey: favoritesKey)
    }
}
