import 'dart:io';

import 'package:flutter/services.dart';

/// Nạp Roboto, phông hệ thống mà theme dùng trên Android (nền mặc định của
/// flutter_test), để đo / chụp chữ đúng như trên máy. App không đóng gói phông
/// chữ (dùng phông hệ thống như Zalo); tệp lấy từ assets/fonts chỉ cho test.
Future<void> loadSystemRobotoForTests() async {
  final loader = FontLoader('Roboto');
  for (final weight in const ['regular', 'medium', 'bold']) {
    loader.addFont(
      File(
        'assets/fonts/roboto-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await loader.load();
}
