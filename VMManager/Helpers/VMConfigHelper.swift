import Foundation
import Virtualization

enum VMConfigHelper {
    static let defaultLaunchOptions = LaunchOptions(cpuCores: recommendedCpuCount, memoryGb: recommendedMemorySize / (1024 * 1024 * 1024), storageGb: recommendedDiskSizeInGib)
    
    static let recommendedCpuCount: UInt = {
        let availableProcessors = UInt(ProcessInfo.processInfo.processorCount)
        
        let maxAmount = UInt(VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        let minAmount = UInt(VZVirtualMachineConfiguration.minimumAllowedCPUCount)
        
        return min(max(availableProcessors - 1, minAmount), maxAmount)
    }()
    
    static let recommendedMemorySize: UInt = {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        let recommendation = availableMemory / 2
        let recommendedMemoryAligned = UInt((recommendation / (1024 * 1024)) * (1024 * 1024))
        
        let maxAmount = UInt(VZVirtualMachineConfiguration.maximumAllowedMemorySize)
        let minAmount = UInt(VZVirtualMachineConfiguration.minimumAllowedMemorySize)
        
        return min(max(recommendedMemoryAligned, minAmount), maxAmount)
    }()
    
    static func recommendedDiskSizeInGib(for url: URL) -> UInt {
        guard let stuff = (try? url.getStorage()) else {
            return 64
        }
        
        return UInt(stuff.available / 2)
    }
    
    static let recommendedDiskSizeInGib: UInt = 64

    static func createBootLoader() -> VZMacOSBootLoader {
        return VZMacOSBootLoader()
    }

    static func createBlockDeviceConfiguration(paths: VmBundlePath) -> VZVirtioBlockDeviceConfiguration {
        do {
            let diskImageAttachment = try VZDiskImageStorageDeviceAttachment(url: paths.diskImageURL, readOnly: false)
            let disk = VZVirtioBlockDeviceConfiguration(attachment: diskImageAttachment)
            return disk
        } catch {
            fatalError("Failed to create Disk image: \(error)")
        }
    }
    
    static func createGraphicsDeviceConfiguration() -> VZMacGraphicsDeviceConfiguration {
        let graphicsConfiguration = VZMacGraphicsDeviceConfiguration()
        
        graphicsConfiguration.displays = [
            // The system arbitrarily chooses the resolution of the display to be 1920 x 1200.
            VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 80)
        ]

        return graphicsConfiguration
    }
    
    static func createNetworkDeviceConfiguration() -> VZVirtioNetworkDeviceConfiguration {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.macAddress = VZMACAddress(string: "d6:a7:58:8e:78:d4")!
        let networkAttachment = VZNATNetworkDeviceAttachment()
        networkDevice.attachment = networkAttachment

        return networkDevice
    }
    
    static func createSoundDeviceConfiguration() -> VZVirtioSoundDeviceConfiguration {
        let audioConfiguration = VZVirtioSoundDeviceConfiguration()

        let inputStream = VZVirtioSoundDeviceInputStreamConfiguration()
        inputStream.source = VZHostAudioInputStreamSource()

        let outputStream = VZVirtioSoundDeviceOutputStreamConfiguration()
        outputStream.sink = VZHostAudioOutputStreamSink()

        audioConfiguration.streams = [inputStream, outputStream]
        return audioConfiguration
    }
    
    static func createPointingDeviceConfiguration() -> VZPointingDeviceConfiguration {
        return VZMacTrackpadConfiguration()
    }

    static func createKeyboardConfiguration() -> [VZKeyboardConfiguration] {
        return [VZUSBKeyboardConfiguration(), VZMacKeyboardConfiguration()]
    }
}


extension URL {
    func getStorage() throws -> (available: Int, total: Int) {
        let resourceValues = try resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ])
        
        let available = resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
        let total = resourceValues.volumeTotalCapacity ?? 0
        
        return (available: Int(available), total: total)
    }
}
