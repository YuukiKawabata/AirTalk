import UIKit
import UserNotifications

final class OnlineAppDelegate: NSObject, UIApplicationDelegate {
  static let tokenReceived = Notification.Name("AirTalk.online.pushToken")
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    NotificationCenter.default.post(name: Self.tokenReceived, object: deviceToken)
  }
  // Registration failures are retried only on the next explicit notification request.
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {}
}
