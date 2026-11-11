import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';
import '../data/meeting_remote_data_source.dart';

final meetingApiProvider = Provider<MeetingApi>((ref) {
  return MeetingRemoteDataSource(ref.watch(apiTransportProvider));
});
