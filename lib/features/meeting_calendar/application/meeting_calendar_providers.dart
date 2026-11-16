import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/foundation_providers.dart';
import '../../conversations/application/use_cases/create_group_use_case.dart';
import '../data/datasources/meeting_calendar_remote_data_source.dart';
import '../data/repositories/meeting_calendar_repository_impl.dart';
import '../domain/repositories/meeting_calendar_repository.dart';
import 'meeting_calendar_use_cases.dart';

final meetingCalendarRepositoryProvider = Provider<MeetingCalendarRepository>((
  ref,
) {
  return MeetingCalendarRepositoryImpl(
    MeetingCalendarRemoteDataSource(ref.watch(apiTransportProvider)),
  );
});

final listMeetingsInRangeUseCaseProvider = Provider<ListMeetingsInRangeUseCase>(
  (ref) =>
      ListMeetingsInRangeUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final getMeetingDetailUseCaseProvider = Provider<GetMeetingDetailUseCase>(
  (ref) =>
      GetMeetingDetailUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final createMeetingUseCaseProvider = Provider<CreateMeetingUseCase>(
  (ref) => CreateMeetingUseCase(
    ref.watch(meetingCalendarRepositoryProvider),
    CreateGroupUseCase(ref.watch(conversationRepositoryProvider)),
  ),
);

final updateMeetingUseCaseProvider = Provider<UpdateMeetingUseCase>(
  (ref) => UpdateMeetingUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final cancelMeetingUseCaseProvider = Provider<CancelMeetingUseCase>(
  (ref) => CancelMeetingUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final respondToMeetingUseCaseProvider = Provider<RespondToMeetingUseCase>(
  (ref) =>
      RespondToMeetingUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final meetingMinutesUseCaseProvider = Provider<MeetingMinutesUseCase>(
  (ref) => MeetingMinutesUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final meetingTasksUseCaseProvider = Provider<MeetingTasksUseCase>(
  (ref) => MeetingTasksUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final checkMeetingConflictsUseCaseProvider =
    Provider<CheckMeetingConflictsUseCase>(
      (ref) => CheckMeetingConflictsUseCase(
        ref.watch(meetingCalendarRepositoryProvider),
      ),
    );

final meetingGuestLinkUseCaseProvider = Provider<MeetingGuestLinkUseCase>(
  (ref) =>
      MeetingGuestLinkUseCase(ref.watch(meetingCalendarRepositoryProvider)),
);

final loadMeetingPeopleUseCaseProvider = Provider<LoadMeetingPeopleUseCase>(
  (ref) => LoadMeetingPeopleUseCase(ref.watch(conversationRepositoryProvider)),
);
