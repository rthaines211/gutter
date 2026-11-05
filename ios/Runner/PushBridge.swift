import Flutter
import UIKit
import UserNotifications

/// Native side of push notifications (channel `app.comic_reader/push`).
///
/// Dart → native: `register` (ask permission, then register with APNs; returns
/// whether permission was granted) and `initialScreen` (the `screen` of a tap
/// that arrived before Dart was listening, once).
/// Native → Dart: `token` {token, env} and `tap` {screen}.
final class PushBridge {
  static let shared = PushBridge()

  private var channel: FlutterMethodChannel?
  private var dartListening = false
  private var launchScreen: String?

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app.comic_reader/push", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
          DispatchQueue.main.async {
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            result(granted)
          }
        }
      case "initialScreen":
        self?.dartListening = true
        result(self?.launchScreen)
        self?.launchScreen = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func didRegister(deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    channel?.invokeMethod("token", arguments: ["token": hex, "env": Self.apsEnvironment()])
  }

  func didTap(screen: String?) {
    if dartListening {
      channel?.invokeMethod("tap", arguments: ["screen": screen as Any])
    } else {
      launchScreen = screen  // cold start: Dart picks it up via initialScreen
    }
  }

  /// Which APNs server issued our token, read from the signing profile.
  /// `make ipad` is a release build with development signing, so the build
  /// mode can't tell us. No profile (App Store) means production.
  static func apsEnvironment() -> String {
    guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
          let data = FileManager.default.contents(atPath: path),
          let text = String(data: data, encoding: .isoLatin1),
          let range = text.range(of: #"<key>aps-environment</key>\s*<string>(\w+)</string>"#,
                                 options: .regularExpression)
    else { return "production" }
    return text[range].contains(">development<") ? "sandbox" : "production"
  }
}
