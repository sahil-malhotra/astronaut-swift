import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

public struct AstronautConfiguration {
    /// Fixed astronaut.sh ingest endpoint — same for every app, so it's not a
    /// caller-supplied option. (The apex astronaut.sh 308-redirects to www.)
    static let baseURL = URL(string: "https://www.astronaut.sh")!

    /// Public app identifier (trk_...) from the astronaut.sh dashboard. Required:
    /// it's how the backend attributes your events to your app.
    public let trackingId: String

    /// When nil, derived from the build: `debug` in DEBUG; otherwise `sandbox`
    /// when the App Store receipt is a sandbox receipt (TestFlight / App Review),
    /// else `release` (the live App Store). Set explicitly to override.
    public let releaseEnvironment: String?

    public init(trackingId: String, releaseEnvironment: String? = nil) {
        self.trackingId = trackingId
        self.releaseEnvironment = releaseEnvironment
    }
}

public final class Astronaut {
    public static let shared = Astronaut()

    private let clickIdKey = "ma_click_id"
    private let sourceKey = "ma_source"
    /// Bumped when first-open semantics changed; avoids a stale `true` from older builds.
    private let hasSentFirstAppOpenKey = "ma_has_sent_first_app_open"
    private let defaults = UserDefaults.standard

    private var configuration: AstronautConfiguration?
    private var deviceId: String
    private let foregroundPresenter = ForegroundNotificationPresenter()

    private init() {
        if let existing = defaults.string(forKey: "ma_device_id") {
            deviceId = existing
        } else {
            let generated = UUID().uuidString
            defaults.set(generated, forKey: "ma_device_id")
            deviceId = generated
        }
    }

    public func configure(_ configuration: AstronautConfiguration) {
        self.configuration = configuration
    }

    public func trackAppOpen(appUserId: String? = nil) {
        let isFirstOpen: Bool
        if defaults.bool(forKey: hasSentFirstAppOpenKey) {
            isFirstOpen = false
        } else {
            defaults.set(true, forKey: hasSentFirstAppOpenKey)
            isFirstOpen = true
        }

        send(
            eventType: "app_open",
            appUserId: appUserId,
            metadata: ["platform": "ios"],
            isFirstOpen: isFirstOpen
        )
    }

    public func trackPurchase(
        revenue: Double,
        currency: String,
        appUserId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        send(
            eventType: "purchase",
            appUserId: appUserId,
            metadata: metadata,
            revenue: revenue,
            currency: currency
        )
    }

    /// Prompts for notification permission and, once granted, registers with
    /// APNs. The resulting device token is delivered to the app delegate's
    /// `didRegisterForRemoteNotificationsWithDeviceToken`, which should forward it
    /// to `handleRemoteNotificationRegistration(deviceToken:)`.
    public func requestPushAuthorization(
        options: UNAuthorizationOptions = [.alert, .badge, .sound]
    ) {
        // Without a delegate, iOS suppresses notification banners while the app
        // is in the foreground. This presenter shows them anyway.
        UNUserNotificationCenter.current().delegate = foregroundPresenter
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
            guard granted else { return }
            #if os(iOS)
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            #endif
        }
    }

    /// Forward this from the app delegate's
    /// `didRegisterForRemoteNotificationsWithDeviceToken`. Resolves the current
    /// authorization status and stores the token.
    public func handleRemoteNotificationRegistration(
        deviceToken: Data,
        appUserId: String? = nil
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.registerPushToken(
                deviceToken: deviceToken,
                permissionStatus: Self.permissionStatusString(settings.authorizationStatus),
                appUserId: appUserId
            )
        }
    }

    /// Maps a `UNAuthorizationStatus` to the `permission_status` value the
    /// analytics backend accepts.
    private static func permissionStatusString(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        case .denied: return "denied"
        case .notDetermined: return "not_determined"
        @unknown default: return "not_determined"
        }
    }

    /// Register (or update) this device's APNs token after the user responds to
    /// the notification permission prompt. Upserts server-side keyed by device,
    /// so a rotated token replaces the previous one. `permissionStatus` is one of
    /// authorized / provisional / ephemeral / denied / not_determined.
    public func registerPushToken(
        deviceToken: Data,
        permissionStatus: String,
        appUserId: String? = nil
    ) {
        guard let configuration else {
            return
        }

        let apnsToken = deviceToken.map { String(format: "%02x", $0) }.joined()

        // APNs tokens are environment-specific: debug builds register against the
        // sandbox gateway, release builds against production.
        let apnsEnvironment: String
        #if DEBUG
        apnsEnvironment = "sandbox"
        #else
        apnsEnvironment = "production"
        #endif

        var payload: [String: Any] = [
            "device_id": deviceId,
            "apns_token": apnsToken,
            "apns_environment": apnsEnvironment,
            "permission_status": permissionStatus,
            "tracking_id": configuration.trackingId,
        ]

        if let appUserId, !appUserId.isEmpty {
            payload["app_user_id"] = appUserId
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(
            url: AstronautConfiguration.baseURL.appendingPathComponent("/api/push-tokens")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request).resume()
    }

    public func send(
        eventType: String,
        appUserId: String?,
        metadata: [String: String],
        revenue: Double? = nil,
        currency: String? = nil,
        isFirstOpen: Bool = false
    ) {
        guard let configuration else {
            return
        }

        let normalizedEventType = eventType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var payload: [String: Any] = [
            "event_type": normalizedEventType,
            "device_id": deviceId,
            "metadata": metadata,
            "tracking_id": configuration.trackingId,
        ]

        if let region = Locale.current.region?.identifier, !region.isEmpty {
            payload["locale_region"] = region
        }

        payload["timezone"] = TimeZone.current.identifier

        let releaseEnvironment: String
        if let custom = configuration.releaseEnvironment, !custom.isEmpty {
            releaseEnvironment = custom
        } else {
            #if DEBUG
            releaseEnvironment = "debug"
            #else
            // Non-debug builds split by App Store receipt: a *production* receipt
            // is the live App Store ("release"); a *sandbox* receipt means the
            // build runs against Apple's sandbox — i.e. TestFlight or an App
            // Review install — so bucket those as "sandbox". Apple Review can't be
            // told apart from TestFlight here (both carry a sandbox receipt), but
            // this keeps reviewer/beta traffic out of your production numbers.
            if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
                releaseEnvironment = "sandbox"
            } else {
                releaseEnvironment = "release"
            }
            #endif
        }
        payload["release_environment"] = releaseEnvironment

        if let clickId = defaults.string(forKey: clickIdKey), !clickId.isEmpty {
            payload["click_id"] = clickId
        }

        if let source = defaults.string(forKey: sourceKey), !source.isEmpty {
            payload["source"] = source
        }

        if let appUserId, !appUserId.isEmpty {
            payload["app_user_id"] = appUserId
        }

        if let revenue {
            payload["revenue"] = revenue
        }

        if let currency, !currency.isEmpty {
            payload["currency"] = currency
        }

        if normalizedEventType == "app_open" {
            payload["is_first_open"] = isFirstOpen ? 1 : 0
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var request = URLRequest(
            url: AstronautConfiguration.baseURL.appendingPathComponent("/api/events")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        URLSession.shared.dataTask(with: request).resume()
    }
}

/// Presents remote notifications as banners even when the app is in the
/// foreground — iOS delivers them silently to the app otherwise.
private final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}
