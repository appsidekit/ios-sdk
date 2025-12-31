# SideKit iOS SDK

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS-blue.svg?style=flat)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat)](https://opensource.org/licenses/MIT)

SideKit is a lightweight iOS SDK that provides seamless version gating and analytics for your mobile applications. Ensure your users are always on the right version and gain insights into app usage with minimal setup.

## Features

- **Version Gating**: Remotely force updates or suggest new versions to your users.
- **Analytics Signals**: Send custom events (signals) to track user behavior and app health.
- **Automatic Presentation**: Out-of-the-box UI for update prompts that works with both SwiftUI and UIKit.
- **Lightweight**: Zero external dependencies and a tiny footprint.

## Installation

### Swift Package Manager

Add SideKit to your project using Swift Package Manager. In Xcode:

1. File > Add Packages...
2. Enter the repository URL: `https://github.com/appsidekit/ios-sdk`
3. Select the version or branch you want to use.

## Usage

### 1. Initialize SideKit

Initialize the SDK as early as possible in your app's lifecycle (e.g., in `AppDelegate` or your SwiftUI `ContentView`).

```swift
.task {
    await SideKit.shared.configure(
        apiKey: "YOUR-API-KEY",
        verbose: true // Optional: enables detailed logs
    )
}
```

### 2. Version Gating

By default, SideKit handles version gating automatically if `presentationMode` is set to `.automatic`. It checks for updates on app launch and whenever the app returns to the foreground.

If you prefer manual control:

```swift
await SideKit.shared.configure(apiKey: "...", presentationMode: .manual)

// In your view
if SideKit.shared.showUpdateScreen {
    // Show your custom update UI
}
```

### 3. Analytics Signals

Send signals to track important events in your app:

```swift
// Send a simple signal
SideKit.shared.sendSignal("user_signed_up")

// Send a signal with a value
SideKit.shared.sendSignal(key: "purchase", value: "pro_plan")
```

## Requirements

- iOS 15.0+ / macOS 15.0+
- Swift 6.0+

## License

SideKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
