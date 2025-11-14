nonisolated
extension String {
    func withoutPrefix(_ prefix: String) -> String {
        guard hasPrefix(prefix) else { return self }
        
        return String(self[index(startIndex, offsetBy: prefix.count)])
    }
    
    func withoutSuffix(_ suffix: String) -> String {
        guard hasSuffix(suffix) else { return self }
        
        return String(self[..<self.index(endIndex, offsetBy: -suffix.count)])
    }
}
