import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/providers.dart';
import '../../l10n/l10n.dart';
import '../../services/notifications/activity_center.dart';

class ActivityCenterScreen extends ConsumerWidget {
  const ActivityCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.watch(activityCenterProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.notificationCenterTitle)),
      body: AnimatedBuilder(
        animation: center,
        builder: (context, _) {
          final entries = center.entries;
          if (entries.isEmpty) {
            return Center(child: Text(context.l10n.notificationsEmpty));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final title = switch (entry.kind) {
                ActivityKind.transcription =>
                  context.l10n.notifTranscriptionCompleted,
                ActivityKind.summary => context.l10n.notifSummaryCompleted,
                ActivityKind.modelDownload => entry.title,
              };
              final subtitle = switch (entry.state) {
                ActivityState.active =>
                  entry.percent == null
                      ? context.l10n.activityInProgress
                      : '${entry.percent}%',
                ActivityState.complete => context.l10n.activityCompleted,
                ActivityState.paused => context.l10n.activityPaused,
                ActivityState.failed => context.l10n.activityFailed,
              };
              final time = DateFormat.yMd(
                Localizations.localeOf(context).toString(),
              ).add_Hm().format(entry.updatedAt);
              return ListTile(
                leading: Icon(
                  entry.kind == ActivityKind.modelDownload
                      ? Icons.download_done
                      : Icons.graphic_eq,
                ),
                title: Text(title),
                subtitle: Text('$subtitle · $time'),
                trailing: entry.read ? null : const Icon(Icons.circle, size: 9),
                onTap: () => Navigator.of(context).pop(entry),
              );
            },
          );
        },
      ),
    );
  }
}
