import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_states.dart';

class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    this.message = 'Bạn không có quyền thực hiện thao tác này.',
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return WebTuiErrorState(
      title: 'Không đủ quyền',
      message: message,
      onRetry: null,
    );
  }
}
