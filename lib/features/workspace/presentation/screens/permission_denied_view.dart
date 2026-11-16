import 'package:flutter/material.dart';

import '../../../../design_system/components/webtui_states.dart';
import '../../../../l10n/app_strings.dart';

class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return WebTuiErrorState(
      title: tr('Không đủ quyền', 'Not enough permission'),
      message:
          message ??
          tr(
            'Bạn không có quyền thực hiện thao tác này.',
            'You do not have permission to do this.',
          ),
      onRetry: null,
    );
  }
}
