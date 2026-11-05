import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var aiBridge: AIRecommendationBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set before launch finishes so a tap that cold-starts the app is delivered.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    PushBridge.shared.didRegister(deviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("push: APNs registration failed: \(error)")
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    PushBridge.shared.didTap(screen: response.notification.request.content.userInfo["screen"] as? String)
    completionHandler()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    aiBridge = AIRecommendationBridge(messenger: engineBridge.applicationRegistrar.messenger())
    PushBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    // Sleep timer -> Shortcuts app (shortcuts:// run-shortcut URL).
    FlutterMethodChannel(
      name: "app.comic_reader/open_url",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      guard call.method == "open", let s = call.arguments as? String, let url = URL(string: s) else {
        result(FlutterMethodNotImplemented)
        return
      }
      UIApplication.shared.open(url) { result($0) }
    }
    // Downloads are re-fetchable: keep them (GBs) out of iCloud backup.
    // Excluding a directory excludes everything under it.
    FlutterMethodChannel(
      name: "app.comic_reader/files",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setMethodCallHandler { call, result in
      // Free space as iOS counts it for user-initiated saves (it can purge
      // caches to make room), in bytes.
      if call.method == "freeSpace" {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        result(values?.volumeAvailableCapacityForImportantUsage.map { Int($0) })
        return
      }
      guard call.method == "excludeFromBackup", let path = call.arguments as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "io", message: "\(error)", details: nil))
      }
    }
  }
}
