import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    // if let flutterVC = window?.rootViewController as? FlutterViewController {
    //   flutterVC.touchRateCorrectionEnabled = false // Disable for low latency
    // }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
