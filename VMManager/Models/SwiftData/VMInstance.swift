import Foundation
import SwiftData

enum URLBookmarkError: Error {
    case dataIsStale
}

@Model
class VMInstance {
    var name: String
    var bundlePath: VmBundlePath
    var pathBookmark: Data
    var createdAt: Date? // TODO: - Make createdAt non-optional, add a finishedInstallingAt variable, and in VmOverviewView add a lastLaunchedAt variable which is set in the VMManagerApp when the app first launches. In VmOverviewView, on appear, check if lastLaunchedAt is more recent than createdAt on Instances that have not yet finished installing. If createdAt is more recent, then that means that during the installation process, the app was closed and the installation was unable to complete.
    var lastRanAt: Date?
    var isLinked: Bool
    
    init(name: String, bundlePath: VmBundlePath, pathBookmark: Data, createdAt: Date? = nil, lastRanAt: Date? = nil, isLinked: Bool = true) {
        self.name = name
        self.bundlePath = bundlePath
        self.pathBookmark = pathBookmark
        self.createdAt = createdAt
        self.lastRanAt = lastRanAt
        self.isLinked = isLinked
    }
    
    func getSecurityScopedURL() throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: pathBookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        if isStale {
            print("Bookmark is stale for \(name)")
            throw URLBookmarkError.dataIsStale
        }
        
        return url
    }
}
