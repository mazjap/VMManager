# VM Manager

A modern, native macOS virtual machine manager built with SwiftUI and Apple's Virtualization framework. Create, launch, and manage macOS virtual machines with a clean, intuitive interface.

![macOS](https://img.shields.io/badge/macOS-26.0+-blue.svg)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)

## Overview

VM Manager provides a streamlined experience for managing macOS virtual machines on Apple Silicon. Built entirely with native Apple technologies, it offers fast performance and deep integration with macOS.

## Features

### Current Features

- **Easy VM Creation** - Multi-step wizard guides you through creating new virtual machines
  - Automatic macOS image download from Apple
  - Custom IPSW file support
  - Configurable CPU, memory, and storage allocation
  - Real-time resource availability checking

- **Simple VM Management** - Clean, visual interface for your virtual machines
  - Launch VMs with a single click
  - Launch in Recovery Mode for troubleshooting
  - Search and sort by name, last run, or creation date
  - Usage statistics and status tracking

- **Smart VM Tracking** - Automatic detection of moved or missing VMs
  - Unlinked VM detection and warnings
  - Easy relinking workflow
  - Import existing VM bundles from filesystem

- **Resource Configuration** - Edit VM resources even after creation
  - Adjust CPU core allocation
  - Modify memory allocation
  - Change disk size
  - Changes persist across launches

- **Sandbox Security** - Proper macOS security integration
  - Security-scoped bookmarks for VM access
  - Secure file access patterns
  - Proper entitlements configuration

### Installation Progress Tracking

- Real-time download progress for macOS images
- Installation progress monitoring
- Automatic cleanup and finalization

## Planned Features

Future enhancements planned for VM Manager:

- **Linux Support** - Create and run Linux virtual machines
- **Advanced Monitoring** - Real-time VM performance metrics and resource usage
- **Snapshot Management** - Create and restore VM snapshots
- **Network Configuration** - Custom network settings and port forwarding
- **Shared Folders** - Easy file sharing between host and guest

## Requirements

- macOS 26.0 (Tahoe) or later
- Apple Silicon Mac (M1, M2, M3, or later)
- Xcode 26.0 or later (for building from source)

## Installation

### Building from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/mazjap/VMManager.git
   cd VMManager
   ```

2. **Open in Xcode**
   ```bash
   open VMManager.xcodeproj
   ```

3. **Build and Run**
   - Select your Mac as the run destination
   - Press `⌘R` to build and run
   - Or use `Product > Archive` to create a distributable app

## Usage

### Creating Your First VM

1. Click the **"+"** button in the toolbar
2. Choose **"Create New"**
3. Follow the setup wizard:
   - **Type**: Select macOS (Linux coming soon)
   - **Name & Location**: Choose a name and storage location
   - **Resources**: Allocate CPU cores, memory, and disk space
   - **Review**: Confirm your settings
4. Click **"Create & Install"** to begin

The VM will automatically download macOS from Apple and complete installation. This process takes approximately 20-30 minutes depending on your internet connection.

### Launching a VM

- **Double-click** a VM in the list to launch it
- Or use the **Play button** on the right side of the row
- For troubleshooting, right-click and select **"Launch in Recovery Mode"**

### Managing VMs

- **Search**: Use the search bar to filter VMs by name
- **Sort**: Click the sort button to organize by name, last run, or creation date
- **Edit Resources**: Right-click a VM and select "Edit Launch Options"
- **Relink**: If a VM shows as "Unlinked", click the relink button to reconnect it
- **Delete**: Right-click and select "Delete" to remove a VM

### Importing Existing VMs

1. Click the **"+"** button
2. Choose **"Import Existing"**
3. Navigate to an existing `.bundle` file
4. The VM will appear in your list immediately

## Architecture

VM Manager is built with:

- **SwiftUI** - Modern, declarative UI framework
- **SwiftData** - Persistent storage for VM metadata
- **Virtualization.framework** - Apple's native VM framework
- **Security-scoped bookmarks** - Secure file access across launches

## Contributing

This project is not currently accepting contributions.

## Acknowledgments

Built with Apple's Virtualization framework and inspired by the need for a simple, native macOS VM manager.

## Support

For issues, questions, or suggestions, please open an issue on GitHub.
