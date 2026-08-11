import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webtui_chat/core/notifications/push_notification_service.dart';

void main() {
  test(
    'latest workspace wins when an older registration completes late',
    () async {
      final coordinator = LatestWorkspaceRegistration();
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final committed = <String>[];

      final firstTicket = coordinator.select('workspace-one');
      final first = coordinator.enqueue(firstTicket, () async {
        firstStarted.complete();
        await releaseFirst.future;
        if (firstTicket.isCurrent) {
          committed.add(firstTicket.workspaceId);
        }
      });
      await firstStarted.future;

      final secondTicket = coordinator.select('workspace-two');
      final second = coordinator.enqueue(secondTicket, () async {
        if (secondTicket.isCurrent) {
          committed.add(secondTicket.workspaceId);
        }
      });

      expect(coordinator.workspaceId, 'workspace-two');
      expect(firstTicket.isCurrent, isFalse);
      releaseFirst.complete();
      await Future.wait([first, second]);

      expect(committed, ['workspace-two']);
    },
  );

  test(
    'failed old registration does not poison queued current workspace',
    () async {
      final coordinator = LatestWorkspaceRegistration();
      final firstStarted = Completer<void>();
      final releaseFailure = Completer<void>();
      var secondRan = false;

      final firstTicket = coordinator.select('workspace-one');
      final first = coordinator.enqueue(firstTicket, () async {
        firstStarted.complete();
        await releaseFailure.future;
        throw StateError('offline');
      });
      await firstStarted.future;

      final secondTicket = coordinator.select('workspace-two');
      final second = coordinator.enqueue(secondTicket, () async {
        secondRan = true;
      });
      final firstFailure = expectLater(first, throwsStateError);
      releaseFailure.complete();

      await firstFailure;
      await second;
      expect(secondRan, isTrue);
      expect(coordinator.workspaceId, 'workspace-two');
    },
  );

  test(
    'clear invalidates routing before queued remote cleanup finishes',
    () async {
      final coordinator = LatestWorkspaceRegistration();
      final registrationStarted = Completer<void>();
      final releaseRegistration = Completer<void>();
      final cleanupStarted = Completer<void>();

      final ticket = coordinator.select('workspace-one');
      final registration = coordinator.enqueue(ticket, () async {
        registrationStarted.complete();
        await releaseRegistration.future;
      });
      await registrationStarted.future;

      final cleanup = coordinator.clearAndEnqueue(() async {
        cleanupStarted.complete();
      });
      expect(coordinator.workspaceId, isNull);
      expect(ticket.isCurrent, isFalse);
      expect(cleanupStarted.isCompleted, isFalse);

      releaseRegistration.complete();
      await Future.wait([registration, cleanup]);
      expect(cleanupStarted.isCompleted, isTrue);
    },
  );

  test(
    'invalidate prevents a disposed service registration from committing',
    () async {
      final coordinator = LatestWorkspaceRegistration();
      final started = Completer<void>();
      final release = Completer<void>();
      var committed = false;

      final ticket = coordinator.select('workspace-one');
      final registration = coordinator.enqueue(ticket, () async {
        started.complete();
        await release.future;
        committed = ticket.isCurrent;
      });
      await started.future;
      coordinator.invalidate();
      release.complete();
      await registration;

      expect(ticket.isCurrent, isFalse);
      expect(coordinator.workspaceId, isNull);
      expect(committed, isFalse);
    },
  );
}
