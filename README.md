# Astronaut (Swift)

Official iOS SDK for [astronaut.sh](https://www.astronaut.sh) — mobile app
analytics, attribution, and push-token registration.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and enter the repository URL, or
add to your `Package.swift`:

```swift
.package(url: "https://github.com/sahil-malhotra/astronaut-swift.git", from: "1.0.0")
```

## Usage

Configure once at launch with your app's **tracking id** (from the astronaut.sh
dashboard → your app), then track events.

```swift
import Astronaut

// In your App init / AppDelegate didFinishLaunching:
Astronaut.shared.configure(
    AstronautConfiguration(
        baseURL: URL(string: "https://www.astronaut.sh")!,
        trackingId: "trk_xxxxxxxxxxxxxxxx"
    )
)

Astronaut.shared.trackAppOpen()
Astronaut.shared.trackPurchase(revenue: 9.99, currency: "USD")
Astronaut.shared.send(eventType: "level_completed", appUserId: nil, metadata: ["level": "3"])
```

### Push notifications (optional)

```swift
// Request permission + register for remote notifications:
Astronaut.shared.requestPushAuthorization()

// Forward the APNs token from your AppDelegate:
func application(_ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Astronaut.shared.handleRemoteNotificationRegistration(deviceToken: deviceToken)
}
```

## Requirements

- iOS 16+
- Swift 5.9+
