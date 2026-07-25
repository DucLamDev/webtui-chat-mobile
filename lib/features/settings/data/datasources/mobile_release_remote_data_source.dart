import '../../../../core/network/api_response.dart';
import '../../../../core/network/api_transport.dart';
import '../../domain/entities/mobile_release_policy.dart';

final class MobileReleaseRemoteDataSource {
  const MobileReleaseRemoteDataSource(this._api);

  final ApiTransport _api;

  Future<MobileReleasePolicy> loadPolicy({
    required String platform,
    required String channel,
    required String currentVersion,
  }) async {
    final response = await _api.get<Object>(
      '/mobile/releases/${_e(platform)}/${_e(channel)}/${_e(currentVersion)}',
    );
    final map = envelopeItem(response.data, 'release');
    final manifestVersion = nullableStringField(map, const [
      'version',
      'latest_version',
      'latestVersion',
    ]);
    return MobileReleasePolicy(
      platform: stringField(map, const ['platform'], fallback: platform),
      channel: stringField(map, const ['channel'], fallback: channel),
      currentVersion: currentVersion,
      minimumVersion: nullableStringField(map, const [
        'minimum_version',
        'minimumVersion',
      ]),
      recommendedVersion:
          nullableStringField(map, const [
            'recommended_version',
            'recommendedVersion',
          ]) ??
          manifestVersion,
      downloadUrl: nullableStringField(map, const [
        'download_url',
        'downloadUrl',
      ]),
      storeUrl: nullableStringField(map, const ['store_url', 'storeUrl']),
      releaseNotes: nullableStringField(map, const [
        'release_notes',
        'releaseNotes',
        'notes',
      ]),
      isRequired: boolField(map, const [
        'required',
        'force_update',
        'forceUpdate',
      ]),
    );
  }
}

String _e(String value) => Uri.encodeComponent(value);
