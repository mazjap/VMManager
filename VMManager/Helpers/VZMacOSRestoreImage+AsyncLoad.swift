import Virtualization

extension VZMacOSRestoreImage {
    static func load(from url: URL) async throws -> VZMacOSRestoreImage {
        do {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<VZMacOSRestoreImage, Error>) in
                VZMacOSRestoreImage.load(from: url, completionHandler: { result in
                    switch result {
                    case let .failure(error):
                        continuation.resume(throwing: NewVMError.whileLoadingIpswFile(at: url, error))
                        return
                    case let .success(restoreImage):
                        continuation.resume(returning: restoreImage)
                        return
                    }
                })
            }
        } catch {
            throw (error as! NewVMError)
        }
    }
}
