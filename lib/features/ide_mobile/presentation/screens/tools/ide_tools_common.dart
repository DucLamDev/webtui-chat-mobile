import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/providers/foundation_providers.dart';
import '../../../../../design_system/tokens/webtui_spacing.dart';
import '../../../../../l10n/app_strings.dart';
import '../../../application/ide_devices_service.dart';
import '../../../application/ide_servers_service.dart';
import '../../../application/ide_tools_service.dart';
import '../../../domain/ide_errors.dart';
import '../../../domain/ide_visible_text.dart';
import '../../controllers/ide_controllers.dart';
import '../../widgets/ide_wb.dart';
import '../more/ide_more_common.dart';

final ideToolsServiceProvider = Provider<IdeToolsService>(
  (ref) => IdeToolsService(ref.watch(ideRpcClientProvider)),
);

final ideServersServiceProvider = Provider<IdeServersService>(
  (ref) => IdeServersService(ref.watch(ideRpcClientProvider)),
);

final ideDevicesServiceProvider = Provider<IdeDevicesService>(
  (ref) => IdeDevicesService(ref.watch(ideRpcClientProvider)),
);

/// IDE có `op` này trong `ready.ops` không (không có thì ẨN nút / phần).
bool ideToolsHas(WidgetRef ref, String op) =>
    ref.watch(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

/// Như [ideToolsHas] nhưng đọc một lần (trong hàm xử lý bấm).
bool ideToolsHasNow(WidgetRef ref, String op) =>
    ref.read(ideLinkStatusProvider).valueOrNull?.ready?.hasOp(op) ?? false;

void ideToolsSnack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

void ideToolsError(BuildContext context, Object e) =>
    ideToolsSnack(context, ideMoreErrorText(e));

Future<void> ideToolsCopy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ideToolsSnack(context, tr('Đã chép', 'Copied'));
}

/// Thời gian giữ bí mật trên clipboard trước khi tự xoá.
const ideSecretClipboardTtl = Duration(seconds: 60);

/// Chép một BÍ MẬT (vd mật khẩu DB): báo sẽ tự xoá sau 60 giây; hết hạn thì
/// đọc clipboard, còn đúng giá trị đó mới xoá (không đè thứ người dùng chép sau).
///
/// Rủi ro còn lại: app bị đóng hẳn trước hạn thì hẹn giờ mất, bí mật ở lại
/// clipboard; ứng dụng khác (hoặc lịch sử clipboard của bàn phím) có thể đọc
/// trong 60 giây đó. Bí mật chỉ nằm trong closure hẹn giờ, không giữ ở nơi khác.
Future<void> ideToolsCopySecret(
  BuildContext context,
  String secret, {
  Duration ttl = ideSecretClipboardTtl,
}) async {
  await Clipboard.setData(ClipboardData(text: secret));
  Timer(ttl, () async {
    try {
      final cur = await Clipboard.getData(Clipboard.kTextPlain);
      if (cur?.text == secret) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } on Object {
      // Không đọc / xoá được clipboard thì thôi.
    }
  });
  if (!context.mounted) return;
  ideToolsSnack(
    context,
    tr(
      'Đã chép, sẽ tự xoá sau 60 giây',
      'Copied, will be cleared in 60 seconds',
    ),
  );
}

// ---------------------------------------------------------------- định dạng

const ideToolsDash = '—';

String ideToolsPct(double? v) => v == null ? ideToolsDash : '${v.round()}%';

String ideToolsNum(double? v) {
  if (v == null) return ideToolsDash;
  return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

/// Byte → KB / MB / GB (cơ số 1024); không hợp lệ → "—".
String ideToolsBytes(double? v) {
  if (v == null || !v.isFinite || v < 0) return ideToolsDash;
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var x = v;
  var i = 0;
  while (x >= 1024 && i < units.length - 1) {
    x /= 1024;
    i++;
  }
  return '${i == 0 || x >= 100 ? x.round() : x.toStringAsFixed(1)} ${units[i]}';
}

/// Giây → "3 ng 4 giờ" / "5 giờ 2 phút" / "7 phút".
String ideToolsDuration(double? seconds) {
  if (seconds == null) return ideToolsDash;
  final s = seconds.floor();
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (d > 0) return tr('$d ngày $h giờ', '${d}d ${h}h');
  if (h > 0) return tr('$h giờ $m phút', '${h}h ${m}m');
  return tr('$m phút', '${m}m');
}

String ideToolsMs(double? ms) {
  if (ms == null) return ideToolsDash;
  if (ms < 1000) return '${ms.round()} ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}

// ---------------------------------------------------------------- thành phần

class ToolSectionTitle extends StatelessWidget {
  const ToolSectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WebTuiSpacing.xs,
      WebTuiSpacing.lg,
      WebTuiSpacing.xs,
      WebTuiSpacing.sm,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: IdeType.titleMedium.copyWith(color: IdeWb.textStrong),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Nút nhỏ vùng bấm ≥ 44.
ButtonStyle ideToolsBtn({Color? color}) => OutlinedButton.styleFrom(
  minimumSize: const Size(44, 44),
  padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
  foregroundColor: color,
  tapTargetSize: MaterialTapTargetSize.padded,
);

ButtonStyle ideToolsFilledBtn() => FilledButton.styleFrom(
  minimumSize: const Size(44, 44),
  padding: const EdgeInsets.symmetric(horizontal: WebTuiSpacing.md),
  tapTargetSize: MaterialTapTargetSize.padded,
);

/// Dòng "nhãn: giá trị" co giãn, không tràn khi chữ lớn.
class ToolInfoRow extends StatelessWidget {
  const ToolInfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      children: [
        Text('$label: ', style: IdeType.bodySmall.copyWith(color: IdeWb.text2)),
        Text(
          ideVisibleText(value),
          style: IdeType.bodySmall.copyWith(color: IdeWb.textStrong),
        ),
      ],
    ),
  );
}

/// Một ô số nhỏ (tổng quan).
class ToolStat extends StatelessWidget {
  const ToolStat(this.label, this.value, {this.color, super.key});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 96),
    child: IdeCard(
      padding: const EdgeInsets.all(WebTuiSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: IdeType.titleMedium.copyWith(
              color: color ?? IdeWb.textStrong,
            ),
          ),
          Text(label, style: IdeType.bodySmall.copyWith(color: IdeWb.text2)),
        ],
      ),
    ),
  );
}

/// Màn chưa có `op` nào dùng được.
Widget ideToolsUnsupported() => const IdeMoreErrorView(error: IdeUnsupported());
