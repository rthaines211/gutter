import Flutter
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// The Files picker for comics (`pickComics` on the `files` channel). The
/// picked files are copied into the app's temp directory (`asCopy`), so the
/// paths it returns need no security scope; Dart deletes each copy after
/// importing it. Answers the Flutter result exactly once: the picked paths,
/// or an empty list on cancel.
private final class ComicPicker: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?

  func pick(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "A file picker is already open", details: nil))
      return
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
    guard var top = window?.rootViewController else {
      result(FlutterError(code: "no_view", message: "No view controller to present from", details: nil))
      return
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    // .cbz has no system type: Info.plist imports one, and whatever the
    // extension resolves to on this device (ours, another app's, or a
    // dynamic type) is what the files are tagged with.
    var types: [UTType] = [.zip]
    if let cbz = UTType(filenameExtension: "cbz") {
      types.insert(cbz, at: 0)
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
    picker.allowsMultipleSelection = true
    picker.delegate = self
    pending = result
    // The default presentation is a sheet on iPhone and iPad: no popover
    // anchor needed.
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(urls.map { $0.path })
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish([])
  }

  private func finish(_ paths: [String]) {
    pending?(paths)
    pending = nil
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var panelBridge: PanelBridge?

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
    panelBridge = PanelBridge(messenger: engineBridge.applicationRegistrar.messenger())
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
    // Excluding a directory excludes everything under it, so Dart flags each
    // server's directory and leaves imported comics (the local source) in.
    // The handler keeps the picker (and so its pending result) alive.
    let comicPicker = ComicPicker()
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
      if call.method == "pickComics" {
        comicPicker.pick(result)
        return
      }
      // Arguments: a path (exclude it), or ["path": String, "exclude": Bool]
      // where false puts the directory back into the backup.
      let args = call.arguments as? [String: Any]
      let pathArg = (call.arguments as? String) ?? (args?["path"] as? String)
      guard call.method == "excludeFromBackup", let path = pathArg else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = (args?["exclude"] as? Bool) ?? true
      do {
        try url.setResourceValues(values)
        result(nil)
      } catch {
        result(FlutterError(code: "io", message: "\(error)", details: nil))
      }
    }
  }
}
