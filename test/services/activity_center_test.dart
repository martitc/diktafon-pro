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

  test(
    'download error code and retained percentage survive read and restart',
    () async {
      final file = File('${directory.path}/history.json');
      final center = ActivityCenter(file);
      await center.put(
        ActivityEntry(
          id: 'model:test',
          kind: ActivityKind.modelDownload,
          title: 'Model',
          state: ActivityState.paused,
          updatedAt: DateTime(2026),
          percent: 63,
          detail: 'HTTP 503',
        ),
      );
      await center.markAllRead();
      final restored = ActivityCenter(file);
      await restored.load();
      expect(restored.entries.single.detail, 'HTTP 503');
      expect(restored.entries.single.percent, 63);
      expect(restored.entries.single.read, isTrue);
    },
  );
}
