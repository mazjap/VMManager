import Foundation
import Synchronization

class DiskUtilityHelper: NSObject, DiskUtilityHelperProtocol {
    func createDiskImage(
        at path: String,
        sizeInGiB: UInt,
        reply: @escaping (Error?) -> Void
    ) {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = [
                "image", "create", "blank",
                "--fs", "none",
                "--format", "ASIF",
                "--size", "\(sizeInGiB)GiB",
                path
            ]
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                reply(nil)
            } else {
                let error = NSError(
                    domain: DiskUtilityErrorDomain,
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create disk image"]
                )
                reply(error)
            }
        } catch {
            reply(error)
        }
    }
    
    func resizeDiskImage(
        at path: String,
        toSizeInGiB newSize: UInt,
        reply: @escaping (Error?) -> Void
    ) {
        let progressDelegate = NSXPCConnection.current()?.remoteObjectProxy as? DiskUtilityProgressDelegate
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = [
                "image", "resize",
                "--size", "\(newSize)GiB",
                path
            ]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            let buffer = Mutex("")
            
            outputPipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                guard !data.isEmpty,
                      let chunk = String(data: data, encoding: .utf8) else { return }
                
                buffer.withLock { $0 += chunk }
                
                let lines = buffer.withLock { $0.split(separator: /(\r\n|\r|\n)/) }
                
                for line in lines.dropLast() {
                    print(line)
                    if let match = line.firstMatch(of: /\[(\d+)% completed\]/) {
                        let percentage = Int(match.1) ?? 0
                        progressDelegate?.didUpdateProgress(percentage)
                    }
                }
                
                buffer.withLock { $0 = lines.last.map(String.init) ?? "" }
            }
            
            try process.run()
            process.waitUntilExit()
            
            outputPipe.fileHandleForReading.readabilityHandler = nil
            
            if process.terminationStatus == 0 {
                reply(nil)
            } else {
                let errorMsg = buffer.withLock { $0.isEmpty ? "Failed to resize disk image" : $0 }
                let error = NSError(
                    domain: DiskUtilityErrorDomain,
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey : errorMsg]
                )
                reply(error)
            }
        } catch {
            reply(error)
        }
    }
}
