import Flutter
import LocalAuthentication
import PushKit
import UIKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?
  private var privacyProtectionEnabled = false
  private var privacyOverlay: UIView?
  private var captureObserver: NSObjectProtocol?
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    pendingDeepLink = (launchOptions?[.url] as? URL)?.absoluteString
    GeneratedPluginRegistrant.register(with: self)
    configureMethodChannels()
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  deinit {
    if let observer = captureObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func configureMethodChannels() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let messenger = controller.binaryMessenger

    let deepLinks = FlutterMethodChannel(name: "webtui/deeplink", binaryMessenger: messenger)
    deepLinks.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialUrl" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(self?.pendingDeepLink)
      self?.pendingDeepLink = nil
    }
    deepLinkChannel = deepLinks

    FlutterMethodChannel(name: "webtui/biometric", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        let context = LAContext()
        var policyError: NSError?
        let available = context.canEvaluatePolicy(
          .deviceOwnerAuthenticationWithBiometrics,
          error: &policyError
        )
        if call.method == "isAvailable" {
          result(available)
          return
        }
        guard call.method == "authenticate" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard available else {
          result(false)
          return
        }
        let arguments = call.arguments as? [String: Any]
        let reason = arguments?["reason"] as? String ?? "Xác thực để mở khóa WebTui Chat"
        context.localizedCancelTitle = "Dùng mã PIN"
        context.evaluatePolicy(
          .deviceOwnerAuthenticationWithBiometrics,
          localizedReason: reason
        ) { success, _ in
          DispatchQueue.main.async { result(success) }
        }
      }

    FlutterMethodChannel(name: "webtui/launcher", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "openUrl" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          let arguments = call.arguments as? [String: Any],
          let rawURL = arguments["url"] as? String,
          let url = URL(string: rawURL),
          let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http"
        else {
          result(FlutterError(code: "INVALID_URL", message: "A valid HTTP(S) URL is required.", details: nil))
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      }

    FlutterMethodChannel(name: "webtui/privacy", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "setSecureScreen" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.setPrivacyProtection(call.arguments as? Bool ?? false)
        result(nil)
      }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.scheme?.lowercased() == "webtui" else {
      return super.application(app, open: url, options: options)
    }
    pendingDeepLink = url.absoluteString
    deepLinkChannel?.invokeMethod("url", arguments: url.absoluteString)
    return true
  }

  private func setPrivacyProtection(_ enabled: Bool) {
    privacyProtectionEnabled = enabled
    if captureObserver == nil {
      captureObserver = NotificationCenter.default.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in self?.refreshCaptureOverlay() }
    }
    refreshCaptureOverlay()
  }

  private func refreshCaptureOverlay() {
    let shouldCover = privacyProtectionEnabled && UIScreen.main.isCaptured
    if !shouldCover {
      privacyOverlay?.removeFromSuperview()
      privacyOverlay = nil
      return
    }
    guard privacyOverlay == nil, let window else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.backgroundColor = .systemBackground
    let label = UILabel(frame: overlay.bounds)
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    label.text = "WebTui Chat"
    label.textAlignment = .center
    label.textColor = .secondaryLabel
    overlay.addSubview(label)
    window.addSubview(overlay)
    privacyOverlay = overlay
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    guard type == .voIP else { return }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    var info = payload.dictionaryPayload
    let callID = (info["call_id"] as? String) ?? (info["id"] as? String) ?? UUID().uuidString
    let caller = (info["body"] as? String) ?? (info["nameCaller"] as? String) ?? "Cuộc gọi đến"
    let mode = (info["mode"] as? String)?.lowercased() ?? "audio"
    info["id"] = callID
    info["nameCaller"] = caller
    info["appName"] = (info["app_name"] as? String) ?? (info["appName"] as? String) ?? "Ứng dụng chat"
    info["handle"] = mode == "video" ? "Cuộc gọi video" : "Cuộc gọi thoại"
    info["type"] = mode == "video" ? 1 : 0
    info["duration"] = 30000
    info["extra"] = payload.dictionaryPayload

    let data = flutter_callkit_incoming.Data(args: info)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data,
      fromPushKit: true,
      completion: completion
    )
  }
}
