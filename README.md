# MobileAnalytics (Swift)

Official iOS SDK for [astronaut.sh](https://www.astronaut.sh) — mobile app
analytics, attribution, and push-token registration.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and enter the repository URL, or
add to your `Package.swift`:

```swift
.package(url: "https://github.com/sahil-malhotra/mobile-analytics-swift.git", from: "1.0.0")
```

## Usage

Configure once at launch with your app's **tracking id** (from the astronaut.sh
dashboard → your app), then track events.

```swift
import MobileAnalytics

// In your App init / AppDelegate didFinishLaunching:
MobileAnalytics.shared.configure(
    MobileAnalyticsConfiguration(
        baseURL: URL(string: "https://www.astronaut.sh")!,
        trackingId: "trk_xxxxxxxxxxxxxxxx"
    )
)

MobileAnalytics.shared.trackAppOpen()
MobileAnalytics.shared.trackPurchase(revenue: 9.99, currency: "USD")
MobileAnalytics.shared.send(eventType: "level_completed", appUserId: nil, metadata: ["level": "3"])
```

### Push notifications (optional)

```swift
// Request permission + register for remote notifications:
MobileAnalytics.shared.requestPushAuthorization()

// Forward the APNs token from your AppDelegate:
func application(_ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    MobileAnalytics.shared.handleRemoteNotificationRegistration(deviceToken: deviceToken)
}
```

## Requirements

- iOS 16+
- Swift 5.9+
