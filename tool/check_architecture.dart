import 'dart:io';

void main() {
  final libDirectory = Directory('lib');
  if (!libDirectory.existsSync()) {
    stderr.writeln('Không tìm thấy thư mục lib/.');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  for (final file in libDirectory.listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) {
      continue;
    }

    final content = file.readAsStringSync();
    if (!_isPresentationSurface(file.path, content)) {
      continue;
    }

    for (final import in _importsFrom(content)) {
      final reason = _bannedImportReason(import);
      if (reason != null) {
        violations.add('${file.path}: import "$import" bị chặn: $reason');
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Kiểm tra kiến trúc mobile thất bại:');
    for (final violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
  }
}

bool _isPresentationSurface(String path, String content) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/presentation/') ||
      content.contains('extends StatelessWidget') ||
      content.contains('extends StatefulWidget') ||
      content.contains('extends ConsumerWidget') ||
      content.contains('extends ConsumerStatefulWidget');
}

Iterable<String> _importsFrom(String content) {
  final importPattern = RegExp(r'''import\s+['"]([^'"]+)['"]''');
  return importPattern.allMatches(content).map((match) => match.group(1)!);
}

String? _bannedImportReason(String import) {
  final normalized = import.toLowerCase();

  if (normalized.startsWith('package:dio')) {
    return 'widget/presentation không gọi Dio trực tiếp';
  }
  if (normalized.startsWith('package:drift')) {
    return 'widget/presentation không truy cập Drift trực tiếp';
  }
  if (normalized.startsWith('package:flutter_secure_storage')) {
    return 'secure storage phải đi qua abstraction';
  }
  if (normalized.startsWith('package:firebase_')) {
    return 'Firebase phải nằm sau adapter/application boundary';
  }
  if (normalized.contains('/dto/') ||
      normalized.contains('_dto.dart') ||
      normalized.contains('/generated/') ||
      normalized.contains('openapi')) {
    return 'DTO/generated OpenAPI client chỉ sống trong data layer';
  }

  return null;
}
