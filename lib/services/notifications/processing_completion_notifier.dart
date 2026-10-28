/// Local notices for completed per-memo transcription and summary jobs.
library;

import 'dart:async';
import 'dart:convert';

import '../processing/job_queue.dart';

abstract interface class ProcessingNotificationSink {
  Future<void> showProcessingComplete(int id, String title, String body);
}

class ProcessingNotificationTexts {
  const ProcessingNotificationTexts({
    required this.transcriptionTitle,
    required this.transcriptionBody,
    required this.summaryTitle,
    required this.summaryBody,
  });

  final String transcriptionTitle;
  final String transcriptionBody;
  final String summaryTitle;
  final String summaryBody;
}

class ProcessingCompletionNotifier {
  ProcessingCompletionNotifier(this._sink, this._texts);

  final ProcessingNotificationSink _sink;
  final ProcessingNotificationTexts _texts;
  StreamSubscription<ProcessingCompletion>? _subscription;
  Future<void> _chain = Future<void>.value();

  void attach(Stream<ProcessingCompletion> completions) {
    _subscription = completions.listen((completion) {
      final (title, body) = switch (completion.stage) {
        ProcessingStage.transcription => (
          _texts.transcriptionTitle,
          _texts.transcriptionBody,
        ),
        ProcessingStage.memoSummary => (
          _texts.summaryTitle,
          _texts.summaryBody,
        ),
      };
      final id = _notificationId(completion);
      _chain = _chain
          .then((_) => _sink.showProcessingComplete(id, title, body))
          .catchError((Object _) {});
    });
  }

  static int _notificationId(ProcessingCompletion completion) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(
      '${completion.stage.name}:${completion.memoId}',
    )) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return 1000 + hash % 0x3ffff000;
  }

  Future<void> dispose() async => _subscription?.cancel();
}
