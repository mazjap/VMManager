import Foundation

class DiskUtilityClient {
    private var connection: NSXPCConnection?
    
    init() {
        setupConnection()
    }
    
    private func setupConnection() {
        let connection = NSXPCConnection(serviceName: "com.mazjap.VMManager.DiskUtilityHelper")
        connection.remoteObjectInterface = NSXPCInterface(with: DiskUtilityHelperProtocol.self)
        
        connection.invalidationHandler = { [weak self] in
            print("XPC connection invalidated")
            self?.connection = nil
        }
        
        connection.interruptionHandler = { [weak self] in
            print("XPC connection interrupted")
            self?.setupConnection()
        }
        
        connection.resume()
        self.connection = connection
    }
    
    func createDiskImage(at path: URL, sizeInGiB: UInt) async throws {
        guard let connection = connection else {
            throw NSError(
                domain: DiskUtilityErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No XPC connection available"]
            )
        }
        
        guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
            assertionFailure("XPC Error: \(error)")
        }) as? DiskUtilityHelperProtocol else {
            throw NSError(
                domain: DiskUtilityErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to connect to helper service"]
            )
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            service.createDiskImage(
                at: path.path(percentEncoded: false),
                sizeInGiB: sizeInGiB
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func resizeDiskImage(
        at path: URL,
        toSizeInGiB newSize: UInt
    ) -> AsyncThrowingStream<Int, Error> {
        guard let connection = connection else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(
                    domain: DiskUtilityErrorDomain,
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No XPC connection available"]
                ))
            }
        }
        
        return AsyncThrowingStream { continuation in
            guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                assertionFailure("XPC Error: \(error)")
            }) as? DiskUtilityHelperProtocol else {
                continuation.finish(throwing: NSError(
                    domain: DiskUtilityErrorDomain,
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to connect to helper service"]
                ))
                return
            }
            
            let delegate = ProgressDelegate { percentage in
                continuation.yield(percentage)
            }
            
            connection.exportedInterface = NSXPCInterface(with: DiskUtilityProgressDelegate.self)
            connection.exportedObject = delegate
            
            service.resizeDiskImage(
                at: path.path(percentEncoded: false),
                toSizeInGiB: newSize
            ) { error in
                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        }
    }
    
    deinit {
        connection?.invalidate()
    }
}

private final class ProgressDelegate: NSObject, DiskUtilityProgressDelegate {
    let handler: @Sendable (Int) -> Void
    
    init(handler: @Sendable @escaping (Int) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func didUpdateProgress(_ percentage: Int) {
        handler(percentage)
    }
}
