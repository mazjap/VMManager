import Foundation

public nonisolated let DiskUtilityErrorDomain = "com.mazjap.VMManager.DiskUtilityHelper"

@objc public protocol DiskUtilityProgressDelegate: Sendable {
    nonisolated func didUpdateProgress(_ percentage: Int)
}

@objc public protocol DiskUtilityHelperProtocol {
    nonisolated func createDiskImage(
        at path: String,
        sizeInGiB: UInt,
        reply: @escaping (Error?) -> Void
    )
    
    nonisolated func resizeDiskImage(
        at path: String,
        toSizeInGiB newSize: UInt,
        reply: @escaping (Error?) -> Void
    )
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "com.mazjap.VMManager.DiskUtilityHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any DiskUtilityHelperProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? DiskUtilityHelperProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/

