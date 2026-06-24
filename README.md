# SideKit iOS SDK
<p align="center">
  <img src="https://appsidekit.com/app-icon.png" width="300" />
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS-blue.svg?style=flat)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat)](https://opensource.org/licenses/MIT)

SideKit is a lightweight iOS SDK that provides seamless version gating and analytics for your mobile applications. Ensure your users are always on the right version and gain insights into app usage with minimal setup.

## Features

- **Version Gating**: Remotely force updates or suggest new versions to your users.
- **Analytics Signals**: Send custom events (signals) to track user behavior and app health.
- **Phone Auth** (alpha): Sign end users in with phone + OTP; the session is persisted across launches.
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

### 4. Analytics Opt-Out

Allow users to control analytics collection. If it's turned off you will no longer have signal data from users with analytics disabled. Version gating will be uninterrupted.

```swift
struct SettingsView: View {
    @ObservedObject var sideKit = SideKit.shared

    var body: some View {
        Toggle("Enable Analytics", isOn: $sideKit.isAnalyticsEnabled)
    }
}
```

Or set it programmatically:

```swift
SideKit.shared.isAnalyticsEnabled = false
```

The preference is automatically persisted across app launches.

### 5. Phone Auth

SideKit currently supports phone as the only sign-in channel. `signIn` sends a one-time
passcode; verifying it creates an account if the user doesn't already have one, otherwise
signs them in. The session is persisted and restored on the next launch.

```swift
// 1. Send a code (creates the account if new, signs in if existing)
let otp = await SideKit.shared.signIn("+15555550100")
guard case .success(let sent) = otp else { return }

// 2. Verify it to complete sign-in
let result = await SideKit.shared.verifyOtp(requestId: sent.requestId, identifier: "+15555550100", code: "123456")
switch result {
case .success(let signIn):
    print("Signed in as \(signIn.user.id)")
    if signIn.isNewUser { /* route to onboarding, e.g. setHandle */ }
case .failure(let err): print("Failed: \(err.code)") // e.g. "invalid_code", "rate_limited"
}

// Read auth state anywhere (SideKit is an ObservableObject)
if SideKit.shared.isAuthenticated { /* ... */ }

// Send the session token to your own backend and verify it via /v1/auth/introspect
let token = SideKit.shared.sessionToken
```

Once signed in you can set a handle (`setHandle`) or sign out (`logout`). Feedback is
automatically attributed to the signed-in user.

## Requirements

- iOS 15.0+ / macOS 15.0+
- Swift 6.0+

## License

SideKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
