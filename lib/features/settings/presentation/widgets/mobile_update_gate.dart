import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/flavor/app_config.dart';
import '../../../../app/providers/foundation_providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/mobile_release_policy.dart';

class MobileUpdateGate extends ConsumerStatefulWidget {
  const MobileUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<MobileUpdateGate> createState() => _MobileUpdateGateState();
}

class _MobileUpdateGateState extends ConsumerState<MobileUpdateGate> {
  String? _shownUpdateKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    final config = ref.read(appConfigProvider);
    if (config.releaseChannel == 'internal') {
      return;
    }
    final result = await ref
        .read(checkMobileReleasePolicyUseCaseProvider)
        .execute();
    if (!mounted) {
      return;
    }
    switch (result) {
      case Success<MobileReleasePolicy>(value: final policy):
        if (!policy.recommendsUpdate) {
          return;
        }
        final updateKey =
            '${policy.channel}:${policy.minimumVersion}:${policy.recommendedVersion}:${policy.isRequired}';
        if (_shownUpdateKey == updateKey) {
          return;
        }
        _shownUpdateKey = updateKey;
        await _showUpdateDialog(policy);
      case FailureResult<MobileReleasePolicy>():
        return;
    }
  }

  Future<void> _showUpdateDialog(MobileReleasePolicy policy) async {
    final updateUrl = _updateUrl(policy);
    await showDialog<void>(
      context: context,
      barrierDismissible: !policy.requiresUpdate,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            policy.requiresUpdate
                ? 'Cần cập nhật ứng dụng'
                : 'Có bản cập nhật mới',
          ),
          content: Text(_message(policy)),
          actions: [
            if (!policy.requiresUpdate)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Để sau'),
              ),
            FilledButton.icon(
              onPressed: updateUrl == null
                  ? null
                  : () async {
                      final opened = await ref
                          .read(externalUrlLauncherProvider)
                          .open(updateUrl);
                      if (!mounted || !dialogContext.mounted) {
                        return;
                      }
                      if (opened) {
                        Navigator.of(dialogContext).pop();
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Không mở được link cập nhật.'),
                        ),
                      );
                    },
              icon: const Icon(Icons.system_update_alt_rounded, size: 18),
              label: const Text('Cập nhật'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

String _message(MobileReleasePolicy policy) {
  final target = policy.minimumVersion ?? policy.recommendedVersion;
  final versionText = target == null ? '' : ' lên phiên bản $target';
  final notes = policy.releaseNotes?.trim();
  final prefix = policy.requiresUpdate
      ? 'Bản hiện tại không còn được hỗ trợ. Hãy cập nhật$versionText để tiếp tục sử dụng.'
      : 'Đã có bản mới$versionText.';
  if (notes == null || notes.isEmpty) {
    return prefix;
  }
  return '$prefix\n\n$notes';
}

String? _updateUrl(MobileReleasePolicy policy) {
  final storeUrl = policy.storeUrl?.trim();
  if (storeUrl != null && storeUrl.isNotEmpty) {
    return storeUrl;
  }
  final downloadUrl = policy.downloadUrl?.trim();
  if (downloadUrl != null && downloadUrl.isNotEmpty) {
    return downloadUrl;
  }
  return null;
}
