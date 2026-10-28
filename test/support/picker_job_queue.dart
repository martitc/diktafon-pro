import 'package:diktafon/services/processing/job_queue.dart';

/// Records the picker's queue handoff without loading native inference engines.
/// Any queue operation other than that handoff remains an unexpected test call.
class PickerJobQueue implements JobQueue {
  int drainCalls = 0;

  @override
  Future<void> drain() async {
    drainCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected picker queue call: ${invocation.memberName}',
  );
}
