import Foundation
import SwiftData
import SwiftUI

@Observable
class InstanceManager: Identifiable {
    let instance: VMInstance
    private let context: ModelContext
    let isInRecoveryMode: Bool
    
    init(instance: VMInstance, context: ModelContext, isInRecoveryMode: Bool) {
        self.instance = instance
        self.context = context
        self.isInRecoveryMode = isInRecoveryMode
    }
    
    var id: PersistentIdentifier {
        instance.id
    }
    
    var name: String {
        get { instance.name }
        set {
            instance.name = newValue
            try? context.save()
        }
    }
    
    var bundlePath: VmBundlePath {
        get {
            do {
                return try VmBundlePath(bundleURL: instance.getSecurityScopedURL())
            } catch URLBookmarkError.dataIsStale {
                self.bundlePath = instance.bundlePath // This should cause the setter to run
                
                do {
                    return try VmBundlePath(bundleURL: instance.getSecurityScopedURL())
                } catch {
                    fatalError("After recreating the bookmark data: \(error)")
                }
            } catch {
                fatalError("Unknown error regarding decoding Bookmark data of path \(instance.bundlePath.url.path(percentEncoded: false)): Error: \(error)")
            }
        }
        set {
            let bookmarkData = Self.createSecurityScopedBookmark(from: newValue.url)
            instance.pathBookmark = bookmarkData
            instance.bundlePath = newValue
            
            try? context.save()
        }
    }
    
    var createdAt: Date? {
        get {
            instance.createdAt
        }
        set {
            if instance.createdAt == nil {
                instance.createdAt = newValue
            }
        }
    }
    
    var lastRanAt: Date? {
        instance.lastRanAt
    }
    
    func didStartVM() {
        print("Started instance")
        instance.lastRanAt = Date()
        try? context.save()
    }
    
    /// InstanceManager instance should be discarded after calling this function
    func delete() {
        context.delete(instance)
        try? context.save()
    }
}

extension InstanceManager {
    convenience init(name: String, path: URL, context: ModelContext, isInRecoveryMode: Bool) {
        let vmBundlePath = VmBundlePath(containerURL: path, bundleName: name)
        self.init(vmBundlePath: vmBundlePath, context: context, isInRecoveryMode: isInRecoveryMode)
    }
    
    convenience init(vmBundlePath: VmBundlePath, context: ModelContext, isInRecoveryMode: Bool) {
        let bookmarkData = Self.createSecurityScopedBookmark(from: vmBundlePath.url)
        let instance = VMInstance(name: vmBundlePath.bundleName, bundlePath: vmBundlePath, pathBookmark: bookmarkData)
        
        context.insert(instance)
        try? context.save() // This is a bad idea
        
        self.init(instance: instance, context: context, isInRecoveryMode: isInRecoveryMode)
    }
    
    static func createSecurityScopedBookmark(from url: URL) -> Data {
        do {
            let hasSecureAccess = url.startAccessingSecurityScopedResource()
            
            defer {
                if hasSecureAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: [
                    .fileSizeKey,
                    .totalFileSizeKey,
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey
                ],
                relativeTo: nil
            )
        } catch {
            fatalError("Could not create bookmark data for the given path \(url.path(percentEncoded: false)), \(error)")
        }
    }
}
