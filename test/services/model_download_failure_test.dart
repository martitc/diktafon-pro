import 'package:background_downloader/background_downloader.dart';
import 'package:diktafon/services/providers/model_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final task = DownloadTask(url: 'https://example.invalid/model');
  test('safe download diagnostics retain HTTP code, never URLs or bodies', () {
    final update = TaskStatusUpdate(
      task,
      TaskStatus.failed,
      TaskHttpException('secret signed URL / sensitive response', 403),
    );
    expect(ModelDownloadFailure.fromUpdate(update).code, 'HTTP 403');
    final network = TaskStatusUpdate(
      task,
      TaskStatus.failed,
      TaskConnectionException('https://secret.invalid/token'),
    );
    expect(ModelDownloadFailure.fromUpdate(network).code, 'NETWORK');
    final disk = TaskStatusUpdate(
      task,
      TaskStatus.failed,
      TaskFileSystemException('/private/model/path'),
    );
    expect(ModelDownloadFailure.fromUpdate(disk).code, 'STORAGE_IO');
  });
}
