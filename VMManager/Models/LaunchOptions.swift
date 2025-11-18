import Foundation

nonisolated
struct LaunchOptions: Hashable, Codable {
    var cpuCores: UInt = 0
    var memoryGb: UInt = 0
    var storageGb: UInt = 0
}

// TODO: - Test the hell out of this
struct BinaryMetadataCoder {
    func encode(_ launchOptions: LaunchOptions) -> Data {
        var data = [UInt8]()
        
        data.append(0)
        data.append(contentsOf: Self.bytesFromUInt(launchOptions.cpuCores))
        data.append(1)
        data.append(contentsOf: Self.bytesFromUInt(launchOptions.memoryGb))
        data.append(2)
        data.append(contentsOf: Self.bytesFromUInt(launchOptions.storageGb))
        
        
        return Data(data)
    }
    
    func decodeLaunchOptions(from data: Data) throws -> LaunchOptions {
        guard data.count >= 27,
              data[0] == 0,
              data[9] == 1,
              data[18] == 2
        else { fatalError("Provided data was not in the correct format") }
        
        var launchOptions = LaunchOptions()
        
        launchOptions.cpuCores = Self.uint(from: Array(data[1...8]))
        launchOptions.memoryGb = Self.uint(from: Array(data[10...17]))
        launchOptions.storageGb = Self.uint(from: Array(data[19...26]))
        
        return launchOptions
    }
    
    static func bytesFromUInt(_ value: UInt) -> [UInt8] {
        let one = UInt8((value >> 56) & 0xff)
        let two = UInt8((value >> 48) & 0xff)
        let three = UInt8((value >> 40) & 0xff)
        let four = UInt8((value >> 32) & 0xff)
        let five = UInt8((value >> 24) & 0xff)
        let six = UInt8((value >> 16) & 0xff)
        let seven = UInt8((value >> 8) & 0xff)
        let eight = UInt8((value) & 0xff)
        
        return [one, two, three, four, five, six, seven, eight]
    }
    
    static func uint(from bytes: [UInt8]) -> UInt {
        var value: UInt = 0
        for (byte, index) in zip(bytes, bytes.indices.reversed()) {
            value |= (UInt(byte) << (index * 8))
        }
        
        return value
    }
}
