// Chuỗi giao diện tự viết (không dùng codegen). Thêm chuỗi mới: khai báo getter
// trong `AppStrings`, rồi điền cả `AppStringsVi` và `AppStringsEn`.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

abstract class AppStrings {
  const AppStrings();

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  /// Không có delegate trong cây (test dựng riêng) thì dùng tiếng Việt.
  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStringsVi();
  }

  static AppStrings forLanguageCode(String languageCode) {
    return languageCode == 'en' ? const AppStringsEn() : const AppStringsVi();
  }

  /// Ngôn ngữ đang dùng cho [tr]. App đặt lại mỗi khi người dùng đổi ngôn ngữ
  /// rồi dựng lại mọi widget; test không đặt thì là tiếng Việt.
  static AppStrings current = const AppStringsVi();

  /// Ngôn ngữ đang là tiếng Anh.
  bool get isEnglish;

  String get tabMessages;
  String get tabFriends;
  String get tabWork;
  String get tabSettings;
  String get back;
  String get save;
  String get cancel;
  String get confirm;
  String get delete;
  String get profileTitle;
  String get accountFallbackName;
  String get switchWorkspace;
  String get workspace;
  String get qrLoginTitle;
  String get qrLoginSubtitle;
  String get advancedTitle;
  String get advancedSubtitle;
  String get notificationsTitle;
  String get notificationsSubtitle;
  String get compactListTitle;
  String get compactListSubtitle;
  String get soundSettings;
  String get logout;
  String get profileLoading;
  String get profileLoadFailed;
  String get changeAvatar;
  String get avatarSheetTitle;
  String get takePhoto;
  String get pickFromLibrary;
  String get fieldDisplayName;
  String get fieldJobTitle;
  String get fieldPhone;
  String get fieldLanguage;
  String get fieldTimezone;
  String get accountSecurityGroup;
  String get accountSecurityTitle;
  String get accountSecuritySubtitle;
  String get appSettingsTitle;
  String get sectionAppearance;
  String get languageTitle;
  String get languageNameVi;
  String get languageNameEn;
  String get themeTitle;
  String get themeSystemSubtitle;
  String get themeSystem;
  String get themeLight;
  String get themeDark;
  String get sectionNotifications;
  String get systemNotificationPermission;
  String get recheck;
  String get allow;
  String get receiveNotifications;
  String get receiveNotificationsSubtitle;
  String get hideSensitivePreview;
  String get hideSensitivePreviewSubtitle;
  String get quietHours;
  String get sectionCalls;
  String get muteMicOnJoin;
  String get muteMicOnJoinSubtitle;
  String get cameraOffOnJoin;
  String get cameraOffOnJoinSubtitle;
  String get sectionAppSecurity;
  String get appLock;
  String get appLockSubtitle;
  String get totpTitle;
  String get totpSubtitle;
  String get sectionOfflineData;
  String get clearWorkspaceCache;
  String get clearWorkspaceCacheSubtitle;
  String get sectionFeedback;
  String get sendFeedback;
  String get sendFeedbackSubtitle;
  String get sectionVersion;
  String get cannotOpenUpdateLink;
  String get checkFailed;
  String get settingsSaveFailed;
  String get notifGranted;
  String get notifProvisional;
  String get notifDenied;
  String get notifUnknown;
  String get notifLabelGranted;
  String get notifLabelProvisional;
  String get notifLabelDenied;
  String get notifLabelAsk;
  String get notifLabelOther;
  String get authToDisableLock;
  String get pinVerifyFailed;
  String get enableAppLockTitle;
  String get pinLabel;
  String get pinRepeat;
  String get enableLock;
  String get pinInvalid;
  String get pinMismatch;
  String get confirmPinTitle;
  String get currentPin;
  String get updateRequired;
  String get updateAvailable;
  String get appUpToDate;
  String get versionCheckHint;
  String get mandatory;
  String get update;
  String get checking;
  String get check;
}

class AppStringsVi extends AppStrings {
  const AppStringsVi();

  @override
  bool get isEnglish => false;

  @override
  String get tabMessages => 'Tin nhắn';

  @override
  String get tabFriends => 'Bạn bè';

  @override
  String get tabWork => 'Công việc';

  @override
  String get tabSettings => 'Cài đặt';

  @override
  String get back => 'Quay lại';

  @override
  String get save => 'Lưu';

  @override
  String get cancel => 'Hủy';

  @override
  String get confirm => 'Xác nhận';

  @override
  String get delete => 'Xóa';

  @override
  String get profileTitle => 'Hồ sơ cá nhân';

  @override
  String get accountFallbackName => 'Tài khoản của bạn';

  @override
  String get switchWorkspace => 'Chuyển workspace';

  @override
  String get workspace => 'Workspace';

  @override
  String get qrLoginTitle => 'Đăng nhập máy tính bằng QR';

  @override
  String get qrLoginSubtitle => 'Quét mã trên trang đăng nhập của máy tính';

  @override
  String get advancedTitle => 'Quyền riêng tư và bảo mật';

  @override
  String get advancedSubtitle => 'Quyền riêng tư, bảo mật và thiết bị';

  @override
  String get notificationsTitle => 'Thông báo';

  @override
  String get notificationsSubtitle => 'Nhận tin nhắn và cảnh báo nhóm';

  @override
  String get compactListTitle => 'Danh sách gọn';

  @override
  String get compactListSubtitle => 'Tăng mật độ thông tin như ảnh reference';

  @override
  String get soundSettings => 'Thiết lập chuông';

  @override
  String get logout => 'Đăng xuất';

  @override
  String get profileLoading => 'Đang tải hồ sơ...';

  @override
  String get profileLoadFailed => 'Không tải được hồ sơ';

  @override
  String get changeAvatar => 'Đổi ảnh đại diện';

  @override
  String get avatarSheetTitle => 'Ảnh đại diện';

  @override
  String get takePhoto => 'Chụp ảnh mới';

  @override
  String get pickFromLibrary => 'Chọn từ thư viện';

  @override
  String get fieldDisplayName => 'Tên hiển thị';

  @override
  String get fieldJobTitle => 'Chức danh';

  @override
  String get fieldPhone => 'Số điện thoại';

  @override
  String get fieldLanguage => 'Ngôn ngữ';

  @override
  String get fieldTimezone => 'Múi giờ';

  @override
  String get accountSecurityGroup => 'Tài khoản và bảo mật';

  @override
  String get accountSecurityTitle => 'Quyền riêng tư và phiên đăng nhập';

  @override
  String get accountSecuritySubtitle =>
      'Thiết bị đang đăng nhập, quyền riêng tư, dữ liệu tài khoản';

  @override
  String get appSettingsTitle => 'Thiết lập ứng dụng';

  @override
  String get sectionAppearance => 'Giao diện';

  @override
  String get languageTitle => 'Ngôn ngữ';

  @override
  String get languageNameVi => 'Tiếng Việt';

  @override
  String get languageNameEn => 'English';

  @override
  String get themeTitle => 'Chủ đề';

  @override
  String get themeSystemSubtitle => 'Theo hệ thống';

  @override
  String get themeSystem => 'Hệ thống';

  @override
  String get themeLight => 'Sáng';

  @override
  String get themeDark => 'Tối';

  @override
  String get sectionNotifications => 'Thông báo';

  @override
  String get systemNotificationPermission => 'Quyền thông báo hệ thống';

  @override
  String get recheck => 'Kiểm tra lại';

  @override
  String get allow => 'Cho phép';

  @override
  String get receiveNotifications => 'Nhận thông báo';

  @override
  String get receiveNotificationsSubtitle =>
      'Tin nhắn, nhóm và cảnh báo workspace';

  @override
  String get hideSensitivePreview => 'Ẩn xem trước nhạy cảm';

  @override
  String get hideSensitivePreviewSubtitle =>
      'Không hiện nội dung trong lock screen';

  @override
  String get quietHours => 'Giờ yên lặng';

  @override
  String get sectionCalls => 'Cuộc gọi';

  @override
  String get muteMicOnJoin => 'Tắt mic khi tham gia';

  @override
  String get muteMicOnJoinSubtitle => 'Tránh tiếng ồn bất ngờ khi vào cuộc gọi';

  @override
  String get cameraOffOnJoin => 'Tắt camera khi tham gia';

  @override
  String get cameraOffOnJoinSubtitle =>
      'Có thể bật lại sau khi đã vào video call';

  @override
  String get sectionAppSecurity => 'Bảo mật ứng dụng';

  @override
  String get appLock => 'Khóa ứng dụng';

  @override
  String get appLockSubtitle =>
      'Yêu cầu PIN hoặc sinh trắc học khi mở lại sau thời gian không dùng';

  @override
  String get totpTitle => 'Xác thực TOTP';

  @override
  String get totpSubtitle => 'Bật mã xác thực và quản lý mã khôi phục';

  @override
  String get sectionOfflineData => 'Dữ liệu offline';

  @override
  String get clearWorkspaceCache => 'Xóa cache workspace';

  @override
  String get clearWorkspaceCacheSubtitle =>
      'Chỉ xóa dữ liệu đọc gần nhất, giữ draft và outbox';

  @override
  String get sectionFeedback => 'Góp ý';

  @override
  String get sendFeedback => 'Gửi góp ý';

  @override
  String get sendFeedbackSubtitle => 'Báo lỗi hoặc đề xuất tính năng mới';

  @override
  String get sectionVersion => 'Phiên bản';

  @override
  String get cannotOpenUpdateLink => 'Không mở được link cập nhật.';

  @override
  String get checkFailed => 'Không kiểm tra được';

  @override
  String get settingsSaveFailed => 'Không lưu được thiết lập';

  @override
  String get notifGranted => 'Đã bật thông báo hệ thống.';

  @override
  String get notifProvisional => 'Thông báo tạm thời đã được bật.';

  @override
  String get notifDenied =>
      'Quyền thông báo đang bị từ chối. Hãy bật trong Cài đặt hệ thống.';

  @override
  String get notifUnknown => 'Không xác định được trạng thái quyền thông báo.';

  @override
  String get notifLabelGranted => 'Đã cho phép thông báo tin nhắn và cuộc gọi';

  @override
  String get notifLabelProvisional => 'Đang cho phép thông báo tạm thời';

  @override
  String get notifLabelDenied => 'Đã từ chối trong cài đặt hệ thống';

  @override
  String get notifLabelAsk => 'Chỉ hỏi quyền khi bạn chọn Cho phép';

  @override
  String get notifLabelOther => 'Trạng thái chưa xác định';

  @override
  String get authToDisableLock => 'Xác thực để tắt khóa ứng dụng';

  @override
  String get pinVerifyFailed => 'Không thể xác minh mã PIN.';

  @override
  String get enableAppLockTitle => 'Bật khóa ứng dụng';

  @override
  String get pinLabel => 'PIN (4-12 số)';

  @override
  String get pinRepeat => 'Nhập lại PIN';

  @override
  String get enableLock => 'Bật khóa';

  @override
  String get pinInvalid => 'PIN phải gồm 4-12 chữ số.';

  @override
  String get pinMismatch => 'Hai mã PIN không khớp.';

  @override
  String get confirmPinTitle => 'Xác nhận mã PIN';

  @override
  String get currentPin => 'Mã PIN hiện tại';

  @override
  String get updateRequired => 'Cần cập nhật ứng dụng';

  @override
  String get updateAvailable => 'Có bản cập nhật mới';

  @override
  String get appUpToDate => 'Ứng dụng hiện tại';

  @override
  String get versionCheckHint => 'Kiểm tra version gate từ backend';

  @override
  String get mandatory => 'Bắt buộc';

  @override
  String get update => 'Cập nhật';

  @override
  String get checking => 'Đang kiểm tra';

  @override
  String get check => 'Kiểm tra';
}

class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  bool get isEnglish => true;

  @override
  String get tabMessages => 'Messages';

  @override
  String get tabFriends => 'Friends';

  @override
  String get tabWork => 'Work';

  @override
  String get tabSettings => 'Settings';

  @override
  String get back => 'Back';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get profileTitle => 'Profile';

  @override
  String get accountFallbackName => 'Your account';

  @override
  String get switchWorkspace => 'Switch workspace';

  @override
  String get workspace => 'Workspace';

  @override
  String get qrLoginTitle => 'Sign in on a computer with QR';

  @override
  String get qrLoginSubtitle => 'Scan the code on the computer\'s sign-in page';

  @override
  String get advancedTitle => 'Privacy and security';

  @override
  String get advancedSubtitle => 'Privacy, security and devices';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsSubtitle => 'Receive messages and group alerts';

  @override
  String get compactListTitle => 'Compact list';

  @override
  String get compactListSubtitle => 'Show more information on each row';

  @override
  String get soundSettings => 'Sound settings';

  @override
  String get logout => 'Log out';

  @override
  String get profileLoading => 'Loading profile...';

  @override
  String get profileLoadFailed => 'Could not load profile';

  @override
  String get changeAvatar => 'Change profile photo';

  @override
  String get avatarSheetTitle => 'Profile photo';

  @override
  String get takePhoto => 'Take a new photo';

  @override
  String get pickFromLibrary => 'Choose from library';

  @override
  String get fieldDisplayName => 'Display name';

  @override
  String get fieldJobTitle => 'Job title';

  @override
  String get fieldPhone => 'Phone number';

  @override
  String get fieldLanguage => 'Language';

  @override
  String get fieldTimezone => 'Time zone';

  @override
  String get accountSecurityGroup => 'Account and security';

  @override
  String get accountSecurityTitle => 'Privacy and sessions';

  @override
  String get accountSecuritySubtitle =>
      'Signed-in devices, privacy and account data';

  @override
  String get appSettingsTitle => 'App settings';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageNameVi => 'Tiếng Việt';

  @override
  String get languageNameEn => 'English';

  @override
  String get themeTitle => 'Theme';

  @override
  String get themeSystemSubtitle => 'Follow system';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get sectionNotifications => 'Notifications';

  @override
  String get systemNotificationPermission => 'System notification permission';

  @override
  String get recheck => 'Check again';

  @override
  String get allow => 'Allow';

  @override
  String get receiveNotifications => 'Receive notifications';

  @override
  String get receiveNotificationsSubtitle =>
      'Messages, groups and workspace alerts';

  @override
  String get hideSensitivePreview => 'Hide sensitive previews';

  @override
  String get hideSensitivePreviewSubtitle =>
      'Do not show content on the lock screen';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get sectionCalls => 'Calls';

  @override
  String get muteMicOnJoin => 'Mute microphone when joining';

  @override
  String get muteMicOnJoinSubtitle => 'Avoid sudden noise when entering a call';

  @override
  String get cameraOffOnJoin => 'Turn camera off when joining';

  @override
  String get cameraOffOnJoinSubtitle =>
      'You can turn it on again after joining the video call';

  @override
  String get sectionAppSecurity => 'App security';

  @override
  String get appLock => 'App lock';

  @override
  String get appLockSubtitle =>
      'Require a PIN or biometrics when reopening after a period of inactivity';

  @override
  String get totpTitle => 'TOTP authentication';

  @override
  String get totpSubtitle =>
      'Turn on authentication codes and manage recovery codes';

  @override
  String get sectionOfflineData => 'Offline data';

  @override
  String get clearWorkspaceCache => 'Clear workspace cache';

  @override
  String get clearWorkspaceCacheSubtitle =>
      'Only clears recently read data; drafts and the send queue are kept';

  @override
  String get sectionFeedback => 'Feedback';

  @override
  String get sendFeedback => 'Send feedback';

  @override
  String get sendFeedbackSubtitle => 'Report a problem or suggest a feature';

  @override
  String get sectionVersion => 'Version';

  @override
  String get cannotOpenUpdateLink => 'Could not open the update link.';

  @override
  String get checkFailed => 'Could not check';

  @override
  String get settingsSaveFailed => 'Could not save settings';

  @override
  String get notifGranted => 'System notifications are on.';

  @override
  String get notifProvisional => 'Provisional notifications are on.';

  @override
  String get notifDenied =>
      'Notification permission is denied. Turn it on in system settings.';

  @override
  String get notifUnknown =>
      'Could not determine the notification permission status.';

  @override
  String get notifLabelGranted => 'Message and call notifications are allowed';

  @override
  String get notifLabelProvisional => 'Provisional notifications are allowed';

  @override
  String get notifLabelDenied => 'Denied in system settings';

  @override
  String get notifLabelAsk =>
      'Permission is only requested when you choose Allow';

  @override
  String get notifLabelOther => 'Status unknown';

  @override
  String get authToDisableLock => 'Authenticate to turn off app lock';

  @override
  String get pinVerifyFailed => 'Could not verify the PIN.';

  @override
  String get enableAppLockTitle => 'Turn on app lock';

  @override
  String get pinLabel => 'PIN (4-12 digits)';

  @override
  String get pinRepeat => 'Re-enter PIN';

  @override
  String get enableLock => 'Turn on lock';

  @override
  String get pinInvalid => 'The PIN must be 4-12 digits.';

  @override
  String get pinMismatch => 'The two PINs do not match.';

  @override
  String get confirmPinTitle => 'Confirm PIN';

  @override
  String get currentPin => 'Current PIN';

  @override
  String get updateRequired => 'App update required';

  @override
  String get updateAvailable => 'A new update is available';

  @override
  String get appUpToDate => 'Current app';

  @override
  String get versionCheckHint => 'Check the version with the server';

  @override
  String get mandatory => 'Required';

  @override
  String get update => 'Update';

  @override
  String get checking => 'Checking';

  @override
  String get check => 'Check';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture<AppStrings>(
      AppStrings.forLanguageCode(locale.languageCode),
    );
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

/// Chữ giao diện viết tại chỗ bằng hai ngôn ngữ: tiếng Việt trước, tiếng Anh
/// sau, ví dụ `tr('Tin nhắn', 'Messages')`. Dùng được cả ngoài widget
/// (controller, định dạng, thông báo lỗi) vì đọc [AppStrings.current].
String tr(String vi, String en) => AppStrings.current.isEnglish ? en : vi;

extension AppStringsContext on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
