import '../../../../core/result/result.dart';
import '../../../../core/result/result_guard.dart';
import '../../data/datasources/mobile_release_remote_data_source.dart';
import '../../domain/entities/mobile_release_policy.dart';

final class CheckMobileReleasePolicyUseCase {
  const CheckMobileReleasePolicyUseCase({
    required MobileReleaseRemoteDataSource remote,
    required String platform,
    required String channel,
    required String currentVersion,
  }) : _remote = remote,
       _platform = platform,
       _channel = channel,
       _currentVersion = currentVersion;

  final MobileReleaseRemoteDataSource _remote;
  final String _platform;
  final String _channel;
  final String _currentVersion;

  Future<Result<MobileReleasePolicy>> execute() {
    return guardResult(
      () => _remote.loadPolicy(
        platform: _platform,
        channel: _channel,
        currentVersion: _currentVersion,
      ),
    );
  }
}
