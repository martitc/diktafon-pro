/// Small durable history for user-facing processing and model-download events.
/// The JSON contains labels, status and local object IDs only; never audio,
/// transcript text, credentials, request bodies or filesystem paths.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum ActivityKind { transcription, summary, modelDownload }

enum ActivityState { active, complete, paused, failed }

@immutable
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.state,
    required this.updatedAt,
    this.targetId,
    this.percent,
    this.read = false,
  });

  final String id;
  final ActivityKind kind;
  final String title;
  final ActivityState state;
  final DateTime updatedAt;
  final String? targetId;
  final int? percent;
  final bool read;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'state': state.name,
    'updatedAt': updatedAt.toIso8601String(),
    'targetId': targetId,
    'percent': percent,
    'read': read,
  };

  factory ActivityEntry.fromJson(Map<String, Object?> json) => ActivityEntry(
    id: json['id']! as String,
    kind: ActivityKind.values.byName(json['kind']! as String),
    title: json['title']! as String,
    state: ActivityState.values.byName(json['state']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    targetId: json['targetId'] as String?,
    percent: json['percent'] as int?,
    read: json['read'] as bool? ?? false,
  );
}

class ActivityCenter extends ChangeNotifier {
  ActivityCenter(this._file);

  final File _file;
  final List<ActivityEntry> _entries = [];
  Future<void> _writes = Future.value();

  List<ActivityEntry> get entries => List.unmodifiable(_entries);
  int get unreadCount => _entries.where((entry) => !entry.read).length;

  Future<void> load() async {
    try {
      if (await _file.exists()) {
        final decoded = jsonDecode(await _file.readAsString()) as List;
        _entries
          ..clear()
          ..addAll(
            decoded.map(
              (item) =>
                  ActivityEntry.fromJson((item as Map).cast<String, Object?>()),
            ),
          );
      }
    } catch (_) {
      _entries.clear();
    }
    notifyListeners();
  }

  Future<void> put(ActivityEntry entry) async {
    _entries.removeWhere((old) => old.id == entry.id);
    _entries.insert(0, entry);
    if (_entries.length > 100) _entries.removeRange(100, _entries.length);
    notifyListeners();
    _writes = _writes.then((_) async {
      try {
        await _file.parent.create(recursive: true);
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(
          jsonEncode(_entries.map((e) => e.toJson()).toList()),
          flush: true,
        );
        await tmp.rename(_file.path);
      } catch (_) {
        // A history write must not interrupt processing or a download.
      }
    });
    await _writes;
  }

  Future<void> markAllRead() async {
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      _entries[i] = ActivityEntry(
        id: e.id,
        kind: e.kind,
        title: e.title,
        state: e.state,
        updatedAt: e.updatedAt,
        targetId: e.targetId,
        percent: e.percent,
        read: true,
      );
    }
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
        flush: true,
      );
      await tmp.rename(_file.path);
    } catch (_) {}
  }
}
