import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/foundation_providers.dart';
import '../../application/ide_more_service.dart';

/// Dịch vụ gọi op của tab Thêm (dùng chung rpc của IDE).
final ideMoreServiceProvider = Provider<IdeMoreService>(
  (ref) => IdeMoreService(ref.watch(ideRpcClientProvider)),
);

/// Bộ chọn ngày (thay được khi test). Trả ngày theo giờ địa phương.
typedef IdeDatePicker =
    Future<DateTime?> Function(BuildContext context, DateTime? initial);

Future<DateTime?> _defaultDatePicker(BuildContext context, DateTime? initial) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5, 12, 31),
  );
}

final ideDatePickerProvider = Provider<IdeDatePicker>(
  (_) => _defaultDatePicker,
);
