import AVFoundation
import CallKit
import Flutter
import LocalAuthentication
import PushKit
import UIKit
import WebRTC
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private var voipRegistry: PKPushRegistry?
  private var privacyProtectionEnabled = false
  private var privacyOverlay: UIView?
  private var captureObserver: NSObjectProtocol?
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?
  private var videoCompressBridge: VideoCompressBridge?
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

    let compressor = VideoCompressBridge(channel: FlutterMethodChannel(
      name: "webtui/video_compress",
      binaryMessenger: messenger
    ))
    compressor.register()
    videoCompressBridge = compressor
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
  // cuộc gọi kết nối nhưng câm cả hai chiều. Plugin flutter_callkit_incoming đã tự fulfill các CXAction.

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

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {}

  func onDecline(_ call: Call, _ action: CXEndCallAction) {}

  func onEnd(_ call: Call, _ action: CXEndCallAction) {}

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
      let input = arguments?["input"] as? String,
      let output = arguments?["output"] as? String,
      !input.isEmpty, !output.isEmpty
    else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Thiếu tham số lấy ảnh bìa.", details: nil))
      return
    }
    let maxSide = (arguments?["maxSide"] as? NSNumber)?.doubleValue ?? 480
    let timeMs = (arguments?["timeMs"] as? NSNumber)?.doubleValue ?? 1000
    guard FileManager.default.fileExists(atPath: input), maxSide > 0 else {
      result(FlutterError(code: "INPUT_MISSING", message: "Không thấy tệp video nguồn.", details: nil))
      return
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
      let asset = AVURLAsset(url: URL(fileURLWithPath: input))
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
