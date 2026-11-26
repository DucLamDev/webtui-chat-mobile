import AVFoundation
import AuthenticationServices
import CallKit
import Flutter
import LocalAuthentication
import PushKit
import UIKit
import WebKit
import WebRTC
import flutter_callkit_incoming
import webview_flutter_wkwebview

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?
  private var privacyProtectionEnabled = false
  private var privacyOverlay: UIView?
  private var captureObserver: NSObjectProtocol?
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?
  private var videoCompressBridge: VideoCompressBridge?
  private var ideWebAuth: IdeWebAuth?
  private var ideWebHost: IdeWebHost?
  private let activeInstanceIDKey = "webtui.active_instance_id"
  private let activeInstanceOriginKey = "webtui.active_instance_origin"
  private let validatedInstanceKey = "webtui.instance_binding_validated"
  private let durableSessionKey = "webtui.session_binding_durable"
  private let callDeviceIDKey = "webtui.call_device_id"
  private let callObserver = CXCallObserver()

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
    // Firebase được khởi động từ Dart, muộn hơn lúc này, nên firebase_messaging
    // bỏ qua bước xin mã APNs khi mở app và iPhone không bao giờ có mã FCM.
    // Bước này không hỏi quyền người dùng; mã Apple được firebase_messaging giữ
    // lại rồi giao cho Firebase khi Dart khởi động xong.
    application.registerForRemoteNotifications()
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
          defaults.removeObject(forKey: self.callDeviceIDKey)
          result(nil)
          return
        }
        if call.method == "setCallDeviceId" {
          guard
            let arguments = call.arguments as? [String: Any],
            let rawDeviceID = arguments["device_id"] as? String
          else {
            result(FlutterError(code: "INVALID_CALL_DEVICE_ID", message: nil, details: nil))
            return
          }
          let deviceID = rawDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !deviceID.isEmpty, deviceID.count <= 128 else {
            result(FlutterError(code: "INVALID_CALL_DEVICE_ID", message: nil, details: nil))
            return
          }
          defaults.set(deviceID, forKey: self.callDeviceIDKey)
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
        // VPSTTT IDE: khoá xác nhận P-256 trong Secure Enclave.
        if IdeDeviceSecurity.handle(call, result: result) { return }
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

    FlutterMethodChannel(name: "webtui/downloads", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "shareFile",
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        let url = URL(fileURLWithPath: path)
        let allowedRoots = [
          FileManager.default.temporaryDirectory,
          FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        ].compactMap { $0?.resolvingSymlinksInPath().path }
        let target = url.resolvingSymlinksInPath().path
        guard allowedRoots.contains(where: { target.hasPrefix($0 + "/") }) else {
          result(FlutterError(code: "BAD_PATH", message: "Tệp không nằm trong thư mục tạm của app.", details: nil))
          return
        }
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let root = self?.window?.rootViewController {
          controller.popoverPresentationController?.sourceView = root.view
          controller.popoverPresentationController?.sourceRect = CGRect(
            x: root.view.bounds.midX, y: root.view.bounds.maxY - 1, width: 1, height: 1)
          root.present(controller, animated: true) { result(nil) }
        } else {
          result(FlutterError(code: "NO_UI", message: "Không có màn hình để chia sẻ.", details: nil))
        }
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

    let compressor = VideoCompressBridge(channel: FlutterMethodChannel(
      name: "webtui/video_compress",
      binaryMessenger: messenger
    ))
    compressor.register()
    videoCompressBridge = compressor
    configureIdeWebChannels(messenger)
  }

  /// VPSTTT IDE nhúng bằng WebView: khoá chip, trình duyệt đăng nhập, cầu nối.
  private func configureIdeWebChannels(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "webtui/ide_web_keys", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in IdeWebDeviceKeys.handle(call, result: result) }

    let auth = IdeWebAuth(anchor: window)
    ideWebAuth = auth
    FlutterMethodChannel(name: "webtui/ide_web_auth", binaryMessenger: messenger)
      .setMethodCallHandler { [weak auth] call, result in
        guard let auth else {
          result(FlutterError(code: "failed", message: nil, details: nil))
          return
        }
        auth.handle(call, result: result)
      }

    let host = IdeWebHost(registrar: registrar(forPlugin: "IdeWebHost"))
    ideWebHost = host
    FlutterMethodChannel(name: "webtui/ide_web_host", binaryMessenger: messenger)
      .setMethodCallHandler { [weak host] call, result in
        guard let host else {
          result(FlutterError(code: "failed", message: nil, details: nil))
          return
        }
        host.handle(call, result: result)
      }
    FlutterEventChannel(name: "webtui/ide_web_host/events", binaryMessenger: messenger)
      .setStreamHandler(host.events)
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
    // Closure trong điều kiện guard phải đặt trong ngoặc (Swift không nhận trailing closure ở đây).
    guard let url = activities.values
      .compactMap({ $0 as? NSUserActivity })
      .first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?
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
      || (host == "ide-web" && url.path == "/callback")
      || (host == "chat" && isAllowedNavigationPath(url.path))
  }

  private func isAllowedNavigationPath(_ path: String) -> Bool {
    if path == "/conversations" || path == "/notifications" { return true }
    // Lời mời workspace /invite/<token> (Flutter kiểm tiếp định dạng token).
    for prefix in ["/conversations/", "/invite/"] where path.hasPrefix(prefix) {
      let identifier = path.dropFirst(prefix.count)
      return !identifier.isEmpty && !identifier.contains("/")
    }
    return false
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
    // Gọi nhóm (Lõi 7): `group_call_invite` / `group_call_cancel` dùng `group_call_id` làm mã cuộc gọi gốc.
    let eventTypeValue = (info["event_type"] as? String)?.lowercased()
    let isGroupCall = eventTypeValue == "group_call_invite" || eventTypeValue == "group_call_cancel"
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
      let callID = (info["call_id"] as? String)
        ?? (isGroupCall ? (info["group_call_id"] as? String) : nil),
      !callID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let workspaceID = info["workspace_id"] as? String,
      !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      completion()
      return
    }
    var caller = (info["body"] as? String) ?? (info["nameCaller"] as? String) ?? "Cuộc gọi đến"
    var mode = (info["mode"] as? String)?.lowercased() ?? "audio"
    if isGroupCall {
      let callerName = (info["caller_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let channelName = (info["channel_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let who = callerName.isEmpty ? "Một thành viên" : callerName
      caller = channelName.isEmpty ? "\(who) đang gọi nhóm" : "\(who) đang gọi nhóm \(channelName)"
      mode = ((info["kind"] as? String)?.lowercased() == "video") ? "video" : "audio"
    }
    info["id"] = callID
    info["workspace_id"] = workspaceID
    info["nameCaller"] = caller
    info["appName"] = (info["app_name"] as? String) ?? (info["appName"] as? String) ?? "Ứng dụng chat"
    info["handle"] = mode == "video" ? "Cuộc gọi video" : "Cuộc gọi thoại"
    info["type"] = mode == "video" ? 1 : 0
    info["duration"] = 30000
    var extra = payload.dictionaryPayload
    if isGroupCall {
      extra["call_id"] = callID
      extra["mode"] = mode
    }
    extra["instance_id"] = payloadInstanceID
    extra["server_base_url"] = activeOrigin
    info["instance_id"] = payloadInstanceID
    info["server_base_url"] = activeOrigin
    info["extra"] = extra

    // Plugin nhận [String: Any?]; payload PushKit có khoá kiểu AnyHashable nên đổi khoá sang String.
    var args = [String: Any?]()
    for (key, value) in info {
      if let key = key as? String {
        args[key] = value
      }
    }
    if payloadString(info, "call_action")?.lowercased() == "cancel" || eventTypeValue == "group_call_cancel" {
      reportCancelledCall(args: args, payload: info, callID: callID, completion: completion)
      return
    }
    let data = flutter_callkit_incoming.Data(args: args)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data,
      fromPushKit: true,
      completion: completion
    )
  }

  // MARK: - VoIP huỷ cuộc gọi (đã nhận ở máy khác / đã kết thúc)
  // PushKit bắt buộc báo CallKit trong completion cho mọi VoIP push, kể cả push huỷ: báo đúng UUID cuộc gọi rồi kết
  // thúc ngay với lý do. Không hiện "cuộc gọi nhỡ" và không bao giờ tắt cuộc gọi đang nói trên chính máy này.

  private func reportCancelledCall(
    args: [String: Any?],
    payload: [AnyHashable: Any],
    callID: String,
    completion: @escaping () -> Void
  ) {
    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      completion()
      return
    }
    var cancelArgs = args
    cancelArgs["missedCallNotification"] = ["showNotification": false]
    let eventType = payloadString(payload, "event_type")?.lowercased()
    // group_call_cancel mang `reason`: accepted_elsewhere | declined | timeout | ended.
    let groupReason = eventType == "group_call_cancel" ? payloadString(payload, "reason")?.lowercased() : nil
    let defaultEndReason: String
    switch groupReason {
    case "accepted_elsewhere": defaultEndReason = "answered_elsewhere"
    case "declined": defaultEndReason = "rejected"
    case "timeout": defaultEndReason = "missed"
    default: defaultEndReason = eventType == "call_answered_elsewhere" ? "answered_elsewhere" : "ended"
    }
    let endReason = payloadString(payload, "end_reason")?.lowercased() ?? defaultEndReason
    let answeredHere = endReason == "answered_elsewhere"
      && isCallAnsweredOnThisDevice(
        callID: callID,
        answeredDeviceID: payloadString(payload, "answered_device_id")
      )
    plugin.reportRemotelyEndedCall(
      flutter_callkit_incoming.Data(args: cancelArgs),
      reason: callKitEndReasonCode(endReason),
      endExistingCall: !answeredHere,
      completion: completion
    )
  }

  /// Mã lý do của plugin (saveEndCall): 2 remoteEnded, 3 unanswered, 4 answeredElsewhere, 5 declinedElsewhere.
  private func callKitEndReasonCode(_ endReason: String) -> Int {
    switch endReason {
    case "answered_elsewhere":
      return 4
    case "rejected":
      return 5
    case "missed":
      return 3
    default:
      return 2
    }
  }

  private func isCallAnsweredOnThisDevice(callID: String, answeredDeviceID: String?) -> Bool {
    if let answered = answeredDeviceID?.trimmingCharacters(in: .whitespacesAndNewlines),
       !answered.isEmpty,
       let local = UserDefaults.standard.string(forKey: callDeviceIDKey),
       !local.isEmpty,
       answered == local || answered == "\(local):voip" {
      return true
    }
    guard let uuid = UUID(uuidString: callID) else { return false }
    // Cuộc gọi đã kết nối trên chính máy này thì không bao giờ tắt theo push "đã nhận ở máy khác".
    return callObserver.calls.contains { $0.uuid == uuid && !$0.hasEnded && $0.hasConnected }
  }

  /// Đọc khoá ở gốc payload, hoặc trong `extra` (lồng tối đa hai lớp như payload call_invite).
  private func payloadString(_ payload: [AnyHashable: Any], _ key: String, depth: Int = 0) -> String? {
    if let value = payload[key] as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return trimmed }
    }
    guard depth < 2, let extra = payload["extra"] as? [AnyHashable: Any] else { return nil }
    return payloadString(extra, key, depth: depth + 1)
  }

  // MARK: - CallKit ↔ WebRTC audio
  // CallKit tự kích hoạt audio session của cuộc gọi; WebRTC phải được báo để khởi động lại micro / loa, nếu không
  // cuộc gọi kết nối nhưng câm cả hai chiều. CallKit chỉ kích hoạt audio session SAU KHI lệnh Nghe được fulfill.
  // Vì AppDelegate này là CallkitIncomingAppDelegate, plugin flutter_callkit_incoming KHÔNG tự fulfill lệnh
  // Nghe / Từ chối / Kết thúc mà giao cho onAccept / onDecline / onEnd: phải fulfill ở đây (trước đây để trống
  // nên bấm Nghe ở màn hình khoá thì CallKit không bao giờ mở âm thanh cho cuộc gọi).

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    let rtcSession = RTCAudioSession.sharedInstance()
    rtcSession.audioSessionDidActivate(audioSession)
    rtcSession.isAudioEnabled = true
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    let rtcSession = RTCAudioSession.sharedInstance()
    rtcSession.audioSessionDidDeactivate(audioSession)
    rtcSession.isAudioEnabled = false
  }

  // Fulfill ngay (như mẫu Speakerbox của Apple): CallKit mở audio session → didActivateAudioSession báo WebRTC.
  // Phần nghe máy với máy chủ (accept, offer / answer) do Dart làm song song qua sự kiện ACTION_CALL_ACCEPT;
  // không chờ WebRTC kết nối mới fulfill (chờ thì CallKit không mở âm thanh kịp).
  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {}

  func providerDidReset() {}
}

/// Kênh `webtui/video_compress`: nén video bằng AVAssetExportSession
/// (cạnh ngắn tối đa 720, MP4). Mọi hàm chạy trên luồng chính.
final class VideoCompressBridge {
  private let channel: FlutterMethodChannel
  private var sessions: [String: AVAssetExportSession] = [:]
  private var timers: [String: Timer] = [:]
  private var cancelled: Set<String> = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  func register() {
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: nil, details: nil))
        return
      }
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "compress":
        self.compress(arguments, result: result)
      case "poster":
        self.poster(arguments, result: result)
      case "cancel":
        if let id = arguments?["id"] as? String, let session = self.sessions[id] {
          self.cancelled.insert(id)
          session.cancelExport()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Lấy một khung hình làm ảnh bìa (JPEG) + kích thước / thời lượng video,
  /// chạy trên hàng đợi nền.
  private func poster(_ arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard
      let output = arguments?["output"] as? String,
      !output.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Thiếu tham số lấy ảnh bìa.", details: nil))
      return
    }
    let maxSide = (arguments?["maxSide"] as? NSNumber)?.doubleValue ?? 480
    let timeMs = (arguments?["timeMs"] as? NSNumber)?.doubleValue ?? 1000
    let sourceURL: URL
    if let inputUrl = arguments?["inputUrl"] as? String, !inputUrl.isEmpty {
      // Đường dẫn phát dần: chỉ nhận http / https.
      guard
        let url = URL(string: inputUrl),
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https", maxSide > 0
      else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Địa chỉ video không hợp lệ.", details: nil))
        return
      }
      sourceURL = url
    } else {
      guard let input = arguments?["input"] as? String, !input.isEmpty else {
        result(FlutterError(code: "INVALID_ARGUMENTS", message: "Thiếu tham số lấy ảnh bìa.", details: nil))
        return
      }
      guard FileManager.default.fileExists(atPath: input), maxSide > 0 else {
        result(FlutterError(code: "INPUT_MISSING", message: "Không thấy tệp video nguồn.", details: nil))
        return
      }
      sourceURL = URL(fileURLWithPath: input)
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let fileManager = FileManager.default
      let outputURL = URL(fileURLWithPath: output)
      let partURL = URL(fileURLWithPath: output + ".part")
      func fail(_ message: String) {
        try? fileManager.removeItem(at: partURL)
        DispatchQueue.main.async {
          result(FlutterError(code: "POSTER_FAILED", message: message, details: nil))
        }
      }
      let asset = AVURLAsset(url: sourceURL)
      guard let track = asset.tracks(withMediaType: .video).first else {
        fail("Tệp không có hình ảnh.")
        return
      }
      let durationSeconds = CMTimeGetSeconds(asset.duration)
      let durationMs = durationSeconds.isFinite && durationSeconds > 0
        ? Int((durationSeconds * 1000).rounded()) : 0
      // Kích thước theo chiều hiển thị: áp preferredTransform.
      let displaySize = track.naturalSize.applying(track.preferredTransform)
      let width = Int(abs(displaySize.width).rounded())
      let height = Int(abs(displaySize.height).rounded())

      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: maxSide, height: maxSide)
      // Video ngắn hơn mốc yêu cầu thì lấy giữa video.
      var seconds = timeMs / 1000
      if durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= seconds {
        seconds = durationSeconds / 2
      }
      let time = CMTime(seconds: seconds, preferredTimescale: 600)
      var actualTime = CMTime.zero
      let cgImage: CGImage
      do {
        cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)
      } catch {
        fail(error.localizedDescription)
        return
      }
      guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8), !data.isEmpty else {
        fail("Không mã hoá được ảnh bìa.")
        return
      }
      do {
        try fileManager.createDirectory(
          at: outputURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: partURL)
        try data.write(to: partURL, options: .atomic)
        try? fileManager.removeItem(at: outputURL)
        try fileManager.moveItem(at: partURL, to: outputURL)
      } catch {
        fail(error.localizedDescription)
        return
      }
      let payload: [String: Any] = [
        "path": output,
        "byteSize": data.count,
        "width": width > 0 ? width : cgImage.width,
        "height": height > 0 ? height : cgImage.height,
        "durationMs": durationMs,
      ]
      DispatchQueue.main.async { result(payload) }
    }
  }

  private func compress(_ arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard
      let id = arguments?["id"] as? String,
      let input = arguments?["input"] as? String,
      let output = arguments?["output"] as? String,
      !id.isEmpty, !input.isEmpty, !output.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Thiếu tham số nén video.", details: nil))
      return
    }
    guard sessions[id] == nil else {
      result(FlutterError(code: "BUSY", message: "Lượt nén này đang chạy.", details: nil))
      return
    }
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: input) else {
      result(FlutterError(code: "INPUT_MISSING", message: "Không thấy tệp video nguồn.", details: nil))
      return
    }
    let outputURL = URL(fileURLWithPath: output)
    // Đuôi .mp4 để AVAssetExportSession nhận đúng kiểu tệp ra.
    let partURL = URL(fileURLWithPath: output + ".part.mp4")
    do {
      try fileManager.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try? fileManager.removeItem(at: partURL)
    } catch {
      result(FlutterError(code: "OUTPUT_FAILED", message: error.localizedDescription, details: nil))
      return
    }

    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    let preset = AVAssetExportSession.exportPresets(compatibleWith: asset)
      .contains(AVAssetExportPreset1280x720)
      ? AVAssetExportPreset1280x720
      : AVAssetExportPresetMediumQuality
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      result(FlutterError(code: "COMPRESS_FAILED", message: "Không tạo được phiên nén video.", details: nil))
      return
    }
    session.outputURL = partURL
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    sessions[id] = session

    let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
      guard let self, let active = self.sessions[id] else { return }
      self.channel.invokeMethod("progress", arguments: ["id": id, "progress": Double(active.progress)])
    }
    timers[id] = timer

    session.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        self.timers[id]?.invalidate()
        self.timers[id] = nil
        self.sessions[id] = nil
        let wasCancelled = self.cancelled.remove(id) != nil
        if wasCancelled || session.status == .cancelled {
          try? fileManager.removeItem(at: partURL)
          result(FlutterError(code: "CANCELLED", message: "Đã huỷ nén video.", details: nil))
          return
        }
        guard session.status == .completed else {
          try? fileManager.removeItem(at: partURL)
          result(FlutterError(
            code: "COMPRESS_FAILED",
            message: session.error?.localizedDescription ?? "Nén video lỗi.",
            details: nil
          ))
          return
        }
        do {
          try? fileManager.removeItem(at: outputURL)
          try fileManager.moveItem(at: partURL, to: outputURL)
          let size = (try fileManager.attributesOfItem(atPath: output)[.size] as? NSNumber)?.intValue ?? 0
          guard size > 0 else {
            result(FlutterError(code: "OUTPUT_FAILED", message: "Tệp video nén rỗng.", details: nil))
            return
          }
          result(["path": output, "byteSize": size])
        } catch {
          try? fileManager.removeItem(at: partURL)
          result(FlutterError(code: "OUTPUT_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

/// Khoá xác nhận P-256 (Face ID / Touch ID mỗi lần ký) cho VPSTTT IDE (kênh `webtui/biometric`).
enum IdeDeviceSecurity {
  // Phần đầu SubjectPublicKeyInfo của khoá công khai P-256 (26 byte), theo sau là điểm X9.63 65 byte.
  private static let p256SpkiHeader = Data([
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ])

  /// true nếu đã xử lý lệnh (là một trong các lệnh khoá xác nhận).
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "createStepKey":
      createStepKey(alias: arguments?["alias"] as? String, result: result)
    case "deleteStepKey":
      deleteStepKey(alias: arguments?["alias"] as? String, result: result)
    case "signWithStepKey":
      signWithStepKey(
        alias: arguments?["alias"] as? String,
        dataBase64: arguments?["data"] as? String,
        reason: arguments?["reason"] as? String ?? "Xác nhận thao tác IDE",
        result: result
      )
    default:
      return false
    }
    return true
  }

  private static func keyError(_ code: String, _ result: FlutterResult) {
    result(FlutterError(code: code, message: code, details: nil))
  }

  /// Dấu bộ sinh trắc học đang đăng ký lúc tạo khoá xác nhận (không bí mật).
  /// Khác dấu hiện tại = đã thêm / xoá vân tay, khuôn mặt: khoá mất hiệu lực.
  private static func domainStateKey(_ alias: String) -> String {
    "ide_step_biometry_state_" + alias
  }

  private enum BiometryState {
    /// Dấu bộ sinh trắc học đang đăng ký (`nil` nếu hệ thống không trả).
    case current(Data?)
    /// Chưa đặt mật mã máy.
    case noPasscode
    /// Chưa đăng ký sinh trắc học.
    case notEnrolled
    /// Máy không có sinh trắc học.
    case noHardware
    /// Tạm không dùng được (khoá vì sai nhiều lần...).
    case unavailable
  }

  private static func biometryState() -> BiometryState {
    let context = LAContext()
    var error: NSError?
    if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      if #available(iOS 18.0, *) {
        return .current(context.domainState.biometry.stateHash)
      }
      return .current(context.evaluatedPolicyDomainState)
    }
    switch (error as? LAError)?.code {
    case .passcodeNotSet: return .noPasscode
    case .biometryNotEnrolled: return .notEnrolled
    case .biometryNotAvailable: return .noHardware
    default: return .unavailable
    }
  }

  /// Xoá khoá xác nhận (gắn lại thành công thì xoá khoá cũ, gắn hỏng thì xoá khoá mới).
  private static func deleteStepKey(alias: String?, result: @escaping FlutterResult) {
    guard let alias = alias, !alias.isEmpty, let tag = alias.data(using: .utf8) else {
      keyError("unavailable", result)
      return
    }
    DispatchQueue.global(qos: .utility).async {
      SecItemDelete(
        [
          kSecClass as String: kSecClassKey,
          kSecAttrApplicationTag as String: tag,
          kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ] as CFDictionary)
      UserDefaults.standard.removeObject(forKey: domainStateKey(alias))
      DispatchQueue.main.async { result(nil) }
    }
  }

  private static func createStepKey(alias: String?, result: @escaping FlutterResult) {
    guard let alias = alias, !alias.isEmpty, let tag = alias.data(using: .utf8) else {
      keyError("unavailable", result)
      return
    }
    // Khoá chỉ mở bằng sinh trắc học đang đăng ký (không nhận mật mã máy): máy
    // phải có mật mã và đã đăng ký Face ID / Touch ID.
    let biometryAtCreation: Data
    switch biometryState() {
    case .current(let state?): biometryAtCreation = state
    case .current(.none), .unavailable:
      keyError("unavailable", result)
      return
    case .noPasscode:
      keyError("notEnrolled", result)
      return
    case .notEnrolled:
      keyError("biometricRequired", result)
      return
    case .noHardware:
      keyError("unsupported", result)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      SecItemDelete(
        [
          kSecClass as String: kSecClassKey,
          kSecAttrApplicationTag as String: tag,
          kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        ] as CFDictionary)
      UserDefaults.standard.removeObject(forKey: domainStateKey(alias))
      var cfError: Unmanaged<CFError>?
      guard
        let access = SecAccessControlCreateWithFlags(
          kCFAllocatorDefault,
          kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
          // Thêm / xoá sinh trắc học thì khoá mất hiệu lực.
          [.privateKeyUsage, .biometryCurrentSet],
          &cfError
        )
      else {
        DispatchQueue.main.async { keyError("notEnrolled", result) }
        return
      }
      var attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecPrivateKeyAttrs as String: [
          kSecAttrIsPermanent as String: true,
          kSecAttrApplicationTag as String: tag,
          kSecAttrAccessControl as String: access,
        ],
      ]
      #if !targetEnvironment(simulator)
        attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
      #endif
      guard
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &cfError),
        let publicKey = SecKeyCopyPublicKey(privateKey),
        let raw = SecKeyCopyExternalRepresentation(publicKey, &cfError) as Data?
      else {
        DispatchQueue.main.async { keyError("unavailable", result) }
        return
      }
      let spki = p256SpkiHeader + raw
      UserDefaults.standard.set(biometryAtCreation, forKey: domainStateKey(alias))
      DispatchQueue.main.async { result(spki.base64EncodedString()) }
    }
  }

  private static func signWithStepKey(
    alias: String?, dataBase64: String?, reason: String, result: @escaping FlutterResult
  ) {
    guard
      let alias = alias, let tag = alias.data(using: .utf8),
      let dataBase64 = dataBase64, let data = Data(base64Encoded: dataBase64)
    else {
      keyError("unavailable", result)
      return
    }
    // Hộp xác nhận chặn luồng gọi, nên ký ở luồng nền.
    DispatchQueue.global(qos: .userInitiated).async {
      // Bộ sinh trắc học đã đổi từ lúc tạo khoá (hoặc khoá tạo bởi bản cũ, nhận
      // cả mật mã máy): khoá không dùng được nữa, phải gắn lại.
      guard let saved = UserDefaults.standard.data(forKey: domainStateKey(alias)) else {
        DispatchQueue.main.async { keyError("key_invalid", result) }
        return
      }
      switch biometryState() {
      case .current(let now?) where now == saved:
        break
      case .current(.none), .unavailable:
        DispatchQueue.main.async { keyError("unavailable", result) }
        return
      default:
        // Đã thêm / xoá sinh trắc học (hoặc xoá hết): khoá mất hiệu lực.
        DispatchQueue.main.async { keyError("key_invalid", result) }
        return
      }
      let context = LAContext()
      context.localizedReason = reason
      let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tag,
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecReturnRef as String: true,
        kSecUseAuthenticationContext as String: context,
      ]
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      guard status == errSecSuccess, let item = item else {
        let code = status == errSecItemNotFound ? "key_missing" : "unavailable"
        DispatchQueue.main.async { keyError(code, result) }
        return
      }
      let privateKey = item as! SecKey
      var cfError: Unmanaged<CFError>?
      guard
        let signature = SecKeyCreateSignature(
          privateKey, .ecdsaSignatureMessageX962SHA256, data as CFData, &cfError)
          as Data?
      else {
        let nsError = cfError?.takeRetainedValue() as Error? as NSError?
        let cancelled =
          nsError?.code == Int(errSecUserCanceled)
          || (nsError?.domain == LAError.errorDomain
            && (nsError?.code == LAError.userCancel.rawValue
              || nsError?.code == LAError.appCancel.rawValue
              || nsError?.code == LAError.systemCancel.rawValue))
        var changed = false
        if !cancelled, case .current(let now?) = biometryState() { changed = now != saved }
        let code = cancelled ? "cancelled" : changed ? "key_invalid" : "unavailable"
        DispatchQueue.main.async { keyError(code, result) }
        return
      }
      // Chữ ký X9.62 đã là DER.
      DispatchQueue.main.async { result(signature.base64EncodedString()) }
    }
  }
}

// MARK: - VPSTTT IDE nhúng bằng WebView (kênh webtui/ide_web_*)

/// Khoá "possession" (kênh `webtui/ide_web_keys`): P-256 trong Secure Enclave, không hỏi sinh trắc,
/// chỉ dùng khi máy đang mở khoá. Khoá sinh trắc vẫn do `webtui/biometric` quản lý; ở đây chỉ xem
/// trạng thái / xoá theo alias.
enum IdeWebDeviceKeys {
  // Phần đầu SubjectPublicKeyInfo của khoá công khai P-256, theo sau là điểm X9.63 65 byte.
  private static let p256SpkiHeader = Data([
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ])
  private static let aliasPrefix = "ideweb."
  private static let installMarkerKey = "webtui.ide_web_keys_installed"
  private static let maxDataBytes = 64 * 1024
  private static let queue = DispatchQueue(label: "webtui.ide_web_keys", qos: .userInitiated)

  private struct Failure: Error {
    let code: String
  }

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let alias = arguments?["alias"] as? String
    switch call.method {
    case "createPossessionKey":
      run(result) { try create(checked(alias, kinds: "p")) }
    case "signPossession":
      let data = (arguments?["data"] as? FlutterStandardTypedData)?.data
      run(result) {
        FlutterStandardTypedData(bytes: try sign(checked(alias, kinds: "p"), data: data))
      }
    case "keyState":
      run(result) { state(try checked(alias, kinds: "pb")) }
    case "biometricState":
      run(result) { biometricState() }
    case "deleteKey":
      run(result) {
        try delete(checked(alias, kinds: "pb"))
        return nil
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func run(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    queue.async {
      purgeKeysOfPreviousInstall()
      let value: Any?
      do {
        value = try work()
      } catch {
        // Không đưa alias hay dữ liệu ký vào lỗi.
        let code = (error as? Failure)?.code ?? "failed"
        value = FlutterError(code: code, message: code, details: nil)
      }
      DispatchQueue.main.async { result(value) }
    }
  }

  /// Keychain còn giữ khoá sau khi gỡ app; bản cài mới (chưa có dấu) không dùng khoá của bản cũ.
  private static func purgeKeysOfPreviousInstall() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: installMarkerKey) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var items: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &items)
    // Máy đang khoá hoặc Keychain lỗi: để lần sau.
    guard status == errSecSuccess || status == errSecItemNotFound else { return }
    for item in (items as? [[String: Any]]) ?? [] {
      guard
        let tag = item[kSecAttrApplicationTag as String] as? Data,
        let alias = String(data: tag, encoding: .utf8),
        alias.hasPrefix(aliasPrefix)
      else { continue }
      let deleted = SecItemDelete(baseQuery(tag) as CFDictionary)
      guard deleted == errSecSuccess || deleted == errSecItemNotFound else { return }
    }
    defaults.set(true, forKey: installMarkerKey)
  }

  private static func baseQuery(_ tag: Data) -> [String: Any] {
    [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    ]
  }

  /// Chỉ nhận alias khoá của IDE nhúng, không đụng khoá khác của app.
  private static func checked(_ alias: String?, kinds: String) throws -> String {
    let pattern = "^ideweb\\.[\(kinds)]\\.[0-9a-f]{24}\\.[A-Za-z0-9_-]{16,128}\\z"
    guard let alias, alias.range(of: pattern, options: .regularExpression) != nil else {
      throw Failure(code: "failed")
    }
    return alias
  }

  private static func create(_ alias: String) throws -> Any? {
    #if targetEnvironment(simulator)
      throw Failure(code: "unsupported")
    #else
      let tag = Data(alias.utf8)
      SecItemDelete(baseQuery(tag) as CFDictionary)
      guard
        let access = SecAccessControlCreateWithFlags(
          kCFAllocatorDefault,
          kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
          .privateKeyUsage,
          nil
        )
      else { throw Failure(code: "failed") }
      let privateAttributes: [String: Any] = [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
        kSecAttrAccessControl as String: access,
      ]
      let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
        kSecPrivateKeyAttrs as String: privateAttributes,
      ]
      var keyError: Unmanaged<CFError>?
      guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &keyError) else {
        let code = (keyError?.takeRetainedValue()).map { CFErrorGetCode($0) }
        throw Failure(code: code == Int(errSecUnimplemented) ? "unsupported" : "failed")
      }
      guard
        let publicKey = SecKeyCopyPublicKey(privateKey),
        let point = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
        point.count == 65
      else {
        SecItemDelete(baseQuery(tag) as CFDictionary)
        throw Failure(code: "failed")
      }
      let spki = (p256SpkiHeader + point).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
      let reply: [String: Any] = ["publicKey": spki, "hardware": "secure_enclave"]
      return reply
    #endif
  }

  private static func sign(_ alias: String, data: Data?) throws -> Data {
    guard let data, !data.isEmpty, data.count <= maxDataBytes else { throw Failure(code: "failed") }
    var query = baseQuery(Data(alias.utf8))
    query[kSecReturnRef as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let item else {
      throw Failure(code: status == errSecItemNotFound ? "key_missing" : "failed")
    }
    let privateKey = item as! SecKey
    // SHA-256 do hệ thống tính; chữ ký X9.62 đã là DER.
    guard
      let signature = SecKeyCreateSignature(
        privateKey, .ecdsaSignatureMessageX962SHA256, data as CFData, nil) as Data?
    else { throw Failure(code: "failed") }
    return signature
  }

  private static func state(_ alias: String) -> Any? {
    var query = baseQuery(Data(alias.utf8))
    query[kSecReturnAttributes as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    // Máy đang khoá: khoá còn đó nhưng chưa dùng được.
    let exists = status == errSecSuccess || status == errSecInteractionNotAllowed
    let attributes = item as? [String: Any]
    let inChip =
      (attributes?[kSecAttrTokenID as String] as? String) == (kSecAttrTokenIDSecureEnclave as String)
    let reply: [String: Any] = [
      "exists": exists,
      "usable": status == errSecSuccess && inChip,
      "hardware": (inChip ? "secure_enclave" : NSNull()) as Any,
    ]
    return reply
  }

  /// Face ID / Touch ID (đều là sinh trắc mạnh).
  private static func biometricState() -> Any? {
    var error: NSError?
    let ready = LAContext().canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &error)
    let code = error?.code
    // Tạm khoá vì thử sai nhiều lần vẫn là máy đã đăng ký.
    let enrolled = ready || code == LAError.Code.biometryLockout.rawValue
    let available = enrolled || code == LAError.Code.biometryNotEnrolled.rawValue
    let reply: [String: Any] = ["available": available, "enrolled": enrolled, "strong": available]
    return reply
  }

  private static func delete(_ alias: String) throws {
    let status = SecItemDelete(baseQuery(Data(alias.utf8)) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw Failure(code: "failed")
    }
    // Dấu bộ sinh trắc học mà `webtui/biometric` lưu kèm khoá sinh trắc cùng alias.
    UserDefaults.standard.removeObject(forKey: "ide_step_biometry_state_" + alias)
  }
}

/// Đăng nhập VPSTTT IDE bằng trình duyệt hệ thống (kênh `webtui/ide_web_auth`). Callback chỉ về
/// phiên này, không qua deep link của app.
@MainActor
final class IdeWebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
  private weak var anchor: UIWindow?
  private var session: ASWebAuthenticationSession?
  private var pending: FlutterResult?
  private var generation = 0

  init(anchor: UIWindow?) {
    self.anchor = anchor
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "authenticate" else {
      result(FlutterMethodNotImplemented)
      return
    }
    let arguments = call.arguments as? [String: Any]
    guard
      let rawURL = arguments?["url"] as? String,
      let url = URL(string: rawURL),
      url.scheme?.lowercased() == "https",
      url.host?.isEmpty == false,
      url.user == nil,
      url.password == nil
    else {
      result(FlutterError(code: "invalid_url", message: "https URL required", details: nil))
      return
    }
    guard arguments?["callbackScheme"] as? String == "webtui" else {
      result(FlutterError(code: "failed", message: "unsupported callback scheme", details: nil))
      return
    }
    // Chỉ một phiên một lúc: mở lượt mới thì lượt cũ coi như huỷ.
    session?.cancel()
    finish(["mode": "cancelled"])

    pending = result
    generation += 1
    let current = generation
    let newSession = ASWebAuthenticationSession(url: url, callbackURLScheme: "webtui") {
      [weak self] callbackURL, error in
      DispatchQueue.main.async { [weak self] in
        // Phiên đã bị thay thì bỏ qua.
        guard let self, self.generation == current else { return }
        self.complete(callbackURL: callbackURL, error: error)
      }
    }
    newSession.presentationContextProvider = self
    newSession.prefersEphemeralWebBrowserSession = true
    session = newSession
    if !newSession.start() {
      finish(FlutterError(code: "failed", message: "cannot open browser", details: nil))
    }
  }

  private func complete(callbackURL: URL?, error: Error?) {
    if let callbackURL,
      callbackURL.scheme?.lowercased() == "webtui",
      callbackURL.host?.lowercased() == "ide-web",
      callbackURL.path == "/callback"
    {
      finish(["mode": "result", "url": callbackURL.absoluteString])
      return
    }
    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
      finish(["mode": "cancelled"])
      return
    }
    finish(FlutterError(code: "failed", message: "failed", details: nil))
  }

  private func finish(_ value: Any) {
    session = nil
    let result = pending
    pending = nil
    result?(value)
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor ?? ASPresentationAnchor()
  }
}

/// Giữ luồng sự kiện `webtui/ide_web_host/events` (gọi ở luồng chính).
final class IdeWebEventStream: NSObject, FlutterStreamHandler {
  private(set) var sink: FlutterEventSink?

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

/// Cầu nối giữa trang VPSTTT IDE trong WebView và app (kênh `webtui/ide_web_host`). Chỉ khung chính
/// đúng origin được gửi yêu cầu; nội dung do phần Dart kiểm và xử lý. Không ghi nhật ký nội dung.
@MainActor
final class IdeWebHost: NSObject {
  let events = IdeWebEventStream()
  private let registrar: FlutterPluginRegistrar?
  private var attachments: [Int64: IdeWebAttachment] = [:]
  private var captureActive = false
  private var captureAny = false

  init(registrar: FlutterPluginRegistrar?) {
    self.registrar = registrar
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    let id = (arguments?["webViewId"] as? NSNumber)?.int64Value
    let attachment = id.flatMap { attachments[$0] }
    switch call.method {
    case "attach":
      guard
        let id,
        let origin = Self.canonicalOrigin(arguments?["allowedOrigin"] as? String),
        let registrar,
        let webView = FWFWebViewFlutterWKWebViewExternalAPI.webView(
          forIdentifier: id, withPluginRegistrar: registrar)
      else {
        result(FlutterError(code: "failed", message: "invalid web view or origin", details: nil))
        return
      }
      detach(id)
      let bridgeEnabled = arguments?["bridgeEnabled"] as? Bool ?? false
      attachments[id] = IdeWebAttachment(
        host: self, id: id, webView: webView, origin: origin, bridgeEnabled: bridgeEnabled)
      refreshCapture()
      result(["supported": true])
    case "detach":
      if let id { detach(id) }
      result(nil)
    case "postReply":
      if let replyId = arguments?["replyId"] as? String,
        let payload = arguments?["payload"] as? String
      {
        attachment?.reply(replyId, payload: payload)
      }
      result(nil)
    case "emit":
      guard
        let payload = arguments?["payload"] as? String,
        (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) is [String: Any]
      else {
        result(FlutterError(code: "failed", message: "payload is not JSON", details: nil))
        return
      }
      attachment?.emit(payload)
      result(nil)
    case "captureState":
      result(["active": captureActive, "any": captureAny])
    case "stopCapture":
      attachment?.stopCapture()
      result(nil)
    case "clearAllData":
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast
      ) {
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func detach(_ id: Int64) {
    guard let attachment = attachments.removeValue(forKey: id) else { return }
    attachment.dispose()
    refreshCapture()
  }

  func refreshCapture() {
    let active = attachments.values.contains { $0.isCapturing }
    let held = attachments.values.contains { $0.holdsMicrophone }
    guard active != captureActive || held != captureAny else { return }
    captureActive = active
    captureAny = held
    events.sink?(["type": "capture", "active": active, "any": held] as [String: Any])
  }

  /// `https://host` (cổng 443, không phần khác) hoặc nil.
  static func canonicalOrigin(_ raw: String?) -> String? {
    guard
      let raw,
      let components = URLComponents(string: raw),
      components.scheme?.lowercased() == "https",
      let host = components.host?.lowercased(),
      host.range(of: "^[a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?\\z", options: .regularExpression) != nil,
      (components.port ?? 443) == 443,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/"
    else { return nil }
    return "https://" + host
  }
}

/// Phần gắn vào một WebView. `WKUserContentController` giữ đối tượng này nên chỉ tham chiếu yếu tới
/// WebView và host.
@MainActor
final class IdeWebAttachment: NSObject, WKScriptMessageHandlerWithReply {
  private typealias Reply = @MainActor (String) -> Void

  private static let handlerName = "appChatNative"
  // `file.save` tối đa 14 MB; phần Dart kiểm hạn chặt hơn cho từng hàm.
  private static let maxMessageLength = 14 * 1024 * 1024
  private static let maxPendingReplies = 32

  private weak var host: IdeWebHost?
  private weak var webView: WKWebView?
  private let id: Int64
  private let origin: String
  private let bridgeEnabled: Bool
  private let script: String
  private var captureObservation: NSKeyValueObservation?
  private var pending: [(id: String, requestHead: String, reply: Reply)] = []
  private var disposed = false

  init(host: IdeWebHost, id: Int64, webView: WKWebView, origin: String, bridgeEnabled: Bool) {
    self.host = host
    self.id = id
    self.webView = webView
    self.origin = origin
    self.bridgeEnabled = bridgeEnabled
    script = Self.bridgeScript(origin: origin)
    super.init()
    #if DEBUG
      if #available(iOS 16.4, *) { webView.isInspectable = true }
    #endif
    captureObservation = webView.observe(\.microphoneCaptureState) { [weak self] _, _ in
      DispatchQueue.main.async { [weak self] in self?.host?.refreshCapture() }
    }
    if bridgeEnabled {
      let controller = webView.configuration.userContentController
      // Đăng ký trùng tên sẽ ném ngoại lệ nên gỡ trước.
      controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
      controller.addScriptMessageHandler(self, contentWorld: .page, name: Self.handlerName)
      controller.addUserScript(
        WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
  }

  var isCapturing: Bool {
    webView?.microphoneCaptureState == WKMediaCaptureState.active
  }

  /// Trang còn giữ micro, kể cả lúc đang bị tắt tiếng.
  var holdsMicrophone: Bool {
    guard let webView else { return false }
    return webView.microphoneCaptureState != WKMediaCaptureState.none
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    captureObservation?.invalidate()
    captureObservation = nil
    // Phải trả lời mọi lượt đang chờ, nếu không trang treo.
    let waiting = pending
    pending.removeAll()
    waiting.forEach { $0.reply(Self.errorReply($0.requestHead, code: "cancelled")) }
    guard bridgeEnabled, let controller = webView?.configuration.userContentController else { return }
    controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
    // WebKit không gỡ được từng script: xoá hết rồi đặt lại script của bên khác.
    let others = controller.userScripts.filter { $0.source != script }
    controller.removeAllUserScripts()
    others.forEach { controller.addUserScript($0) }
  }

  func stopCapture() {
    webView?.setMicrophoneCaptureState(WKMediaCaptureState.none, completionHandler: nil)
  }

  func reply(_ replyId: String, payload: String) {
    guard let index = pending.firstIndex(where: { $0.id == replyId }) else { return }
    pending.remove(at: index).reply(payload)
  }

  func emit(_ payload: String) {
    guard bridgeEnabled, !disposed, let webView else { return }
    // Nội dung đi bằng đối số (WebKit tự mã hoá), không ghép vào mã.
    webView.callAsyncJavaScript(
      """
      if (location.origin === origin) {
        window.dispatchEvent(new CustomEvent('appchat:event', { detail: JSON.parse(payload) }));
      }
      return true;
      """,
      arguments: ["origin": origin, "payload": payload],
      in: nil,
      in: .page,
      completionHandler: { _ in }
    )
  }

  // MARK: WKScriptMessageHandlerWithReply

  #if compiler(>=6.0)
    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage,
      replyHandler: @escaping @MainActor (Any?, String?) -> Void
    ) {
      receive(message) { replyHandler($0, nil) }
    }
  #else
    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage,
      replyHandler: @escaping (Any?, String?) -> Void
    ) {
      receive(message) { replyHandler($0, nil) }
    }
  #endif

  private func receive(_ message: WKScriptMessage, reply: @escaping Reply) {
    let json = message.body as? String
    let source = message.frameInfo.securityOrigin
    let trusted =
      message.frameInfo.isMainFrame
      && source.protocol.lowercased() == "https"
      && (source.port == 0 || source.port == 443)
      && "https://" + source.host.lowercased() == origin
    guard trusted else {
      reply(Self.errorReply(json, code: "forbidden_origin"))
      return
    }
    guard let json else {
      reply(Self.errorReply(nil, code: "bad_request"))
      return
    }
    guard json.utf16.count <= Self.maxMessageLength else {
      reply(Self.errorReply(json, code: "too_large"))
      return
    }
    guard !disposed, let sink = host?.events.sink else {
      reply(Self.errorReply(json, code: "failed"))
      return
    }
    // Trả lời bị bỏ (trang đã đổi) không được chiếm chỗ mãi: đầy thì huỷ lượt cũ nhất.
    while pending.count >= Self.maxPendingReplies {
      let oldest = pending.removeFirst()
      oldest.reply(Self.errorReply(oldest.requestHead, code: "busy"))
    }
    let replyId = UUID().uuidString.lowercased()
    pending.append((id: replyId, requestHead: String(json.prefix(512)), reply: reply))
    sink([
      "type": "message",
      "webViewId": NSNumber(value: id),
      "id": replyId,
      "json": json,
      "isMainFrame": true,
      "origin": origin,
    ] as [String: Any])
  }

  private static func errorReply(_ json: String?, code: String) -> String {
    // Chỉ dò mã yêu cầu ở đầu chuỗi: không đọc cả thân lớn chỉ để báo lỗi.
    var requestId = ""
    if let json {
      let head = String(json.prefix(512))
      if let match = head.range(
        of: "\"id\"\\s*:\\s*\"[A-Za-z0-9_-]{1,64}\"", options: .regularExpression)
      {
        requestId = String(head[match].dropLast().split(separator: "\"").last ?? "")
      }
    }
    let body: [String: Any] = [
      "v": 1, "id": requestId, "ok": false,
      "error": ["code": code, "message": code],
    ]
    guard
      let data = try? JSONSerialization.data(withJSONObject: body),
      let text = String(data: data, encoding: .utf8)
    else { return "{}" }
    return text
  }

  private static func bridgeScript(origin: String) -> String {
    // `origin` chỉ gồm chữ thường, số, dấu chấm, gạch ngang (xem canonicalOrigin).
    """
    (function () {
      'use strict';
      if (window !== window.top || location.origin !== '\(origin)') return;
      if (Object.prototype.hasOwnProperty.call(window, 'AppChatBridge')) return;
      var native = window.webkit && window.webkit.messageHandlers
        && window.webkit.messageHandlers.\(handlerName);
      if (!native) return;
      function newId() {
        var bytes = crypto.getRandomValues(new Uint8Array(16)), id = '';
        for (var i = 0; i < bytes.length; i++) id += ('0' + bytes[i].toString(16)).slice(-2);
        return id;
      }
      var bridge = Object.create(null);
      bridge.request = function (method, params) {
        var id = newId();
        function failure(code) {
          return { v: 1, id: id, ok: false, error: { code: code, message: code } };
        }
        var body;
        try {
          body = JSON.stringify(
            { v: 1, id: id, method: method, params: params === undefined ? {} : params });
        } catch (e) {
          return Promise.resolve(failure('bad_request'));
        }
        return native.postMessage(body).then(
          function (text) { return JSON.parse(text); }
        ).catch(function () { return failure('failed'); });
      };
      Object.defineProperty(window, 'AppChatBridge', { value: Object.freeze(bridge) });
    })();
    """
  }
}
