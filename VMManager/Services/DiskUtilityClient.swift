import Foundation

enum DiskUtilityError: Error {
    static let domain = DiskUtilityErrorDomain
    
    case noXPCConnectionAvailable
    case failedToConnectToXPCService
    case resizeError(Error)
    case createError(Error)
}

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
    
    func createDiskImage(at path: URL, sizeInGiB: UInt) async throws(DiskUtilityError) {
        guard let connection = connection else {
            throw DiskUtilityError.noXPCConnectionAvailable
        }
        
        guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
            assertionFailure("XPC Error: \(error)")
        }) as? DiskUtilityHelperProtocol else {
            throw DiskUtilityError.failedToConnectToXPCService
        }
        
        do {
            return try await withCheckedThrowingContinuation { continuation in
                service.createDiskImage(
                    at: path.path(percentEncoded: false),
                    sizeInGiB: sizeInGiB
                ) { error in
                    if let error {
                        continuation.resume(throwing: DiskUtilityError.createError(error))
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            throw error as! DiskUtilityError
        }
    }
    
    func resizeDiskImage(
        at path: URL,
        toSizeInGiB newSize: UInt
    ) -> AsyncThrowingStream<Int, Error> {
        guard let connection = connection else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: DiskUtilityError.noXPCConnectionAvailable)
            }
        }
        
        return AsyncThrowingStream { continuation in
            guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                assertionFailure("XPC Error: \(error)")
            }) as? DiskUtilityHelperProtocol else {
                continuation.finish(throwing: DiskUtilityError.failedToConnectToXPCService)
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
                    continuation.finish(throwing: DiskUtilityError.resizeError(error))
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
