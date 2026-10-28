import 'dart:io';

import 'package:diktafon/services/notifications/activity_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(
    () => directory = Directory.systemTemp.createTempSync('activity-test-'),
  );
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'retains the newest 100 events across restarts and marks them read',
    () async {
      final file = File('${directory.path}/history.json');
      final center = ActivityCenter(file);
      await center.load();
      for (var i = 0; i < 102; i++) {
        await center.put(
          ActivityEntry(
            id: 'event-$i',
            kind: ActivityKind.transcription,
            title: 'Done',
            state: ActivityState.complete,
            updatedAt: DateTime(2026, 1, 1, 0, i),
            targetId: 'memo-$i',
          ),
        );
      }
      expect(center.entries, hasLength(100));
      expect(center.entries.first.id, 'event-101');
      final restored = ActivityCenter(file);
      await restored.load();
      expect(restored.entries.last.id, 'event-2');
      expect(restored.unreadCount, 100);
      await restored.markAllRead();
      expect(restored.unreadCount, 0);
    },
  );
}
