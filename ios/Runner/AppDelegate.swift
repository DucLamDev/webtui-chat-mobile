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
  private let activeInstanceIDKey = "webtui.active_instance_id"
  private let activeInstanceOriginKey = "webtui.active_instance_origin"
  private let validatedInstanceKey = "webtui.instance_binding_validated"
  private let durableSessionKey = "webtui.session_binding_durable"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launchURL = launchOptions?[.url] as? URL
    pendingDeepLink = launchURL.flatMap { isTrustedCustomLink($0) ? $0.absoluteString : nil }
      ?? launchUniversalLink(from: launchOptions)?.absoluteString
    GeneratedPluginRegistrant.register(with: self)
    configureMethodChannels()
    sanitizePersistedInstanceBinding()
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

    FlutterMethodChannel(name: "webtui/instance_binding", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(FlutterError(code: "UNAVAILABLE", message: nil, details: nil))
          return
        }
        let defaults = UserDefaults.standard
        if call.method == "clearValidatedInstance" {
          defaults.set(false, forKey: self.validatedInstanceKey)
          defaults.set(false, forKey: self.durableSessionKey)
          defaults.removeObject(forKey: self.activeInstanceIDKey)
          defaults.removeObject(forKey: self.activeInstanceOriginKey)
          result(nil)
          return
        }
        if call.method == "setSessionDurability" {
          guard
            let arguments = call.arguments as? [String: Any],
            let durable = arguments["durable_session"] as? Bool
          else {
            result(FlutterError(code: "INVALID_SESSION_DURABILITY", message: nil, details: nil))
            return
          }
          defaults.set(durable, forKey: self.durableSessionKey)
          if durable,
             let instanceID = defaults.string(forKey: self.activeInstanceIDKey),
             instanceID == instanceID.lowercased(),
             UUID(uuidString: instanceID) != nil,
             let origin = defaults.string(forKey: self.activeInstanceOriginKey),
             self.canonicalHTTPSOrigin(origin) == origin {
            defaults.set(true, forKey: self.validatedInstanceKey)
          } else {
            defaults.set(false, forKey: self.validatedInstanceKey)
          }
          result(nil)
          return
        }
        guard
          call.method == "setValidatedInstance",
          let arguments = call.arguments as? [String: Any],
          let rawInstanceID = arguments["instance_id"] as? String,
          UUID(uuidString: rawInstanceID) != nil,
          let rawOrigin = arguments["origin"] as? String,
          let origin = self.canonicalHTTPSOrigin(rawOrigin),
          let durable = arguments["durable_session"] as? Bool
        else {
          result(FlutterError(code: "INVALID_INSTANCE_BINDING", message: nil, details: nil))
          return
        }
        defaults.set(rawInstanceID.lowercased(), forKey: self.activeInstanceIDKey)
        defaults.set(origin, forKey: self.activeInstanceOriginKey)
        defaults.set(durable, forKey: self.durableSessionKey)
        defaults.set(durable, forKey: self.validatedInstanceKey)
        result(nil)
      }

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
        let reason = arguments?["reason"] as? String ?? "Xác thực để mở khóa WebTUI Chat"
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
    guard isTrustedCustomLink(url) else {
      return false
    }
    pendingDeepLink = url.absoluteString
    deepLinkChannel?.invokeMethod("url", arguments: url.absoluteString)
    let flutterHandled = super.application(app, open: url, options: options)
    return flutterHandled || deepLinkChannel != nil
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else {
      return super.application(
        application,
        continue: userActivity,
        restorationHandler: restorationHandler
      )
    }
    guard
      let url = userActivity.webpageURL,
      isTrustedUniversalLink(url)
    else {
      return false
    }
    pendingDeepLink = url.absoluteString
    deepLinkChannel?.invokeMethod("url", arguments: url.absoluteString)
    let flutterHandled = super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
    return flutterHandled || deepLinkChannel != nil
  }

  private func launchUniversalLink(
    from launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> URL? {
    guard
      let activities = launchOptions?[.userActivityDictionary]
        as? [AnyHashable: Any]
    else { return nil }
    guard let url = activities.values
      .compactMap { $0 as? NSUserActivity }
      .first { $0.activityType == NSUserActivityTypeBrowsingWeb }?
      .webpageURL
    else { return nil }
    return isTrustedUniversalLink(url) ? url : nil
  }

  private func isTrustedUniversalLink(_ url: URL) -> Bool {
    return url.scheme?.lowercased() == "https"
      && url.host?.lowercased() == "chat.vpsttt.com"
      && (url.port == nil || url.port == 443)
      && url.user == nil
      && url.password == nil
      && url.fragment == nil
      && isAllowedNavigationPath(url.path)
  }

  private func isTrustedCustomLink(_ url: URL) -> Bool {
    guard
      url.scheme?.lowercased() == "webtui",
      url.user == nil,
      url.password == nil,
      url.port == nil,
      url.fragment == nil
    else { return false }
    let host = url.host?.lowercased()
    return (host == "oidc" && url.path == "/callback")
      || (host == "chat" && isAllowedNavigationPath(url.path))
  }

  private func isAllowedNavigationPath(_ path: String) -> Bool {
    if path == "/conversations" || path == "/notifications" { return true }
    let prefix = "/conversations/"
    guard path.hasPrefix(prefix) else { return false }
    let identifier = path.dropFirst(prefix.count)
    return !identifier.isEmpty && !identifier.contains("/")
  }

  private func canonicalHTTPSOrigin(_ rawValue: String) -> String? {
    guard
      let components = URLComponents(string: rawValue),
      components.scheme?.lowercased() == "https",
      let host = components.host?.lowercased(),
      !host.isEmpty,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/"
    else { return nil }
    var normalized = URLComponents()
    normalized.scheme = "https"
    normalized.host = host
    if let port = components.port, port != 443 {
      normalized.port = port
    }
    return normalized.string
  }

  private func sanitizePersistedInstanceBinding() {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: validatedInstanceKey),
          defaults.bool(forKey: durableSessionKey) else {
      defaults.set(false, forKey: validatedInstanceKey)
      return
    }
    guard
      let instanceID = defaults.string(forKey: activeInstanceIDKey),
      instanceID == instanceID.lowercased(),
      UUID(uuidString: instanceID) != nil,
      let origin = defaults.string(forKey: activeInstanceOriginKey),
      canonicalHTTPSOrigin(origin) == origin
    else {
      defaults.set(false, forKey: validatedInstanceKey)
      defaults.set(false, forKey: durableSessionKey)
      defaults.removeObject(forKey: activeInstanceIDKey)
      defaults.removeObject(forKey: activeInstanceOriginKey)
      return
    }
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
    label.text = "WebTUI Chat"
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
    let defaults = UserDefaults.standard
    let payloadInstanceID = info["instance_id"] as? String
    guard
      defaults.bool(forKey: validatedInstanceKey),
      defaults.bool(forKey: durableSessionKey),
      let activeInstanceID = defaults.string(forKey: activeInstanceIDKey),
      activeInstanceID == activeInstanceID.lowercased(),
      UUID(uuidString: activeInstanceID) != nil,
      let payloadInstanceID,
      payloadInstanceID == payloadInstanceID.lowercased(),
      UUID(uuidString: payloadInstanceID) != nil,
      payloadInstanceID == activeInstanceID,
      let activeOrigin = defaults.string(forKey: activeInstanceOriginKey),
      canonicalHTTPSOrigin(activeOrigin) == activeOrigin,
      let callID = info["call_id"] as? String,
      !callID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let workspaceID = info["workspace_id"] as? String,
      !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      completion()
      return
    }
    let caller = (info["body"] as? String) ?? (info["nameCaller"] as? String) ?? "Cuộc gọi đến"
    let mode = (info["mode"] as? String)?.lowercased() ?? "audio"
    info["id"] = callID
    info["workspace_id"] = workspaceID
    info["nameCaller"] = caller
    info["appName"] = (info["app_name"] as? String) ?? (info["appName"] as? String) ?? "Ứng dụng chat"
    info["handle"] = mode == "video" ? "Cuộc gọi video" : "Cuộc gọi thoại"
    info["type"] = mode == "video" ? 1 : 0
    info["duration"] = 30000
    var extra = payload.dictionaryPayload
    extra["instance_id"] = payloadInstanceID
    extra["server_base_url"] = activeOrigin
    info["instance_id"] = payloadInstanceID
    info["server_base_url"] = activeOrigin
    info["extra"] = extra

    let data = flutter_callkit_incoming.Data(args: info)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data,
      fromPushKit: true,
      completion: completion
    )
  }
}
