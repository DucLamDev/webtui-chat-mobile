import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_voice.dart';
import '../../domain/repositories/message_attachment_repository.dart';

final class AudioMessageAttachmentRepository
    implements MessageVoiceRecorderRepository {
  AudioMessageAttachmentRepository({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _activePath;
  final Stopwatch _elapsed = Stopwatch();
  final List<double> _levels = [];
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  /// Lấy mẫu mức âm mỗi 100 ms (đủ cho 64 cột sóng âm); tối đa 1 giờ.
  static const _amplitudeInterval = Duration(milliseconds: 100);
  static const _maxLevelSamples = 36000;

  void dispose() {
    _stopSampling();
    _recorder.dispose();
  }

  void _startSampling() {
    _stopSampling();
    _levels.clear();
    _elapsed
      ..reset()
      ..start();
    try {
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(_amplitudeInterval)
          .listen(
            (amplitude) {
              if (_levels.length < _maxLevelSamples) {
                _levels.add(amplitude.current);
              }
            },
            // Máy không đọc được biên độ: chỉ gửi thời lượng, bỏ sóng âm.
            onError: (_) {},
          );
    } on Object {
      _amplitudeSubscription = null;
    }
  }

  void _stopSampling() {
    _elapsed.stop();
    unawaited(_amplitudeSubscription?.cancel());
    _amplitudeSubscription = null;
  }

  MessageVoiceMetadata _voiceMetadata() {
    return MessageVoiceMetadata(
      durationMs: _elapsed.elapsedMilliseconds
          .clamp(0, maxVoiceDurationMs)
          .toInt(),
      waveform: voiceWaveformFromLevels(_levels),
    );
  }

  @override
  Future<Result<void>> start() async {
    try {
      if (await _recorder.isRecording()) {
        return const Success(null);
      }
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        return const FailureResult(
          Failure(
            kind: FailureKind.forbidden,
            message:
                'Chưa có quyền microphone. Vào Cài đặt để cấp quyền ghi âm.',
            code: 'VOICE_MICROPHONE_PERMISSION_DENIED',
          ),
        );
      }

      final directory = await getTemporaryDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = p.join(directory.path, fileName);
      _activePath = path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _startSampling();
      return const Success(null);
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể bắt đầu ghi âm. Kiểm tra quyền microphone.',
          code: 'VOICE_RECORD_START_FAILED',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<PickedMessageAttachment?>> stop() async {
    try {
      final stoppedPath = await _recorder.stop();
      _stopSampling();
      final voice = _voiceMetadata();
      _levels.clear();
      final path = stoppedPath ?? _activePath;
      _activePath = null;
      if (path == null || path.trim().isEmpty) {
        return const Success(null);
      }

      final file = File(path);
      if (!await file.exists()) {
        return const Success(null);
      }
      final stat = await file.stat();
      if (stat.size <= 0) {
        await file.delete().catchError((_) => file);
        return const FailureResult(
          Failure(
            kind: FailureKind.validation,
            message: 'Bản ghi âm quá ngắn, hãy thử ghi lại.',
            code: 'VOICE_RECORD_EMPTY',
          ),
        );
      }
      return Success(
        PickedMessageAttachment(
          path: path,
          fileName: p.basename(path),
          mimeType: 'audio/mp4',
          byteSize: stat.size,
          kind: MessageAttachmentKind.audio,
          voice: voice,
        ),
      );
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể lưu bản ghi âm. Hãy thử lại.',
          code: 'VOICE_RECORD_STOP_FAILED',
          cause: error,
        ),
      );
    }
  }

  @override
  Future<Result<void>> cancel() async {
    try {
      await _recorder.cancel();
      _stopSampling();
      _levels.clear();
      final path = _activePath;
      _activePath = null;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      return const Success(null);
    } on Object catch (error) {
      return FailureResult(
        Failure(
          kind: FailureKind.storage,
          message: 'Không thể hủy ghi âm.',
          code: 'VOICE_RECORD_CANCEL_FAILED',
          cause: error,
        ),
      );
    }
  }
}
