import 'package:flutter/material.dart';

import '../models/work_project.dart';

String shortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

const _wib = Duration(hours: 7);
String _digits(int value) => value.toString().padLeft(2, '0');

String wibDateTime(DateTime time) {
  final date = time.toUtc().add(_wib);
  return '${shortDate(date)} ${_digits(date.hour)}:${_digits(date.minute)} WIB';
}

Future<DateTime?> selectDeadline(BuildContext context, DateTime now) async {
  final today = now.toUtc().add(_wib);
  final date = await showDatePicker(
    context: context,
    initialDate: today.add(const Duration(days: 2)),
    firstDate: today,
    lastDate: today.add(const Duration(days: 365)),
    helpText: 'Pilih tanggal deadline (WIB)',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: const TimeOfDay(hour: 17, minute: 0),
    helpText: 'Pilih jam deadline (WIB)',
  );
  if (time == null) return null;
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  ).subtract(_wib);
}

String? deadlineReminder(
  WorkProject project,
  DateTime? now, {
  bool detail = false,
}) {
  if (project.status == ProjectStatus.completed ||
      project.status == ProjectStatus.waitingReview) {
    return null;
  }
  if (now == null) return detail ? 'Menunggu waktu server' : null;
  final remaining = project.effectiveDeadline.difference(now);
  final minutes = remaining.inMinutes.abs();
  final duration = [
    if (minutes >= 1440) '${minutes ~/ 1440} h',
    if (minutes >= 60) '${(minutes ~/ 60) % 24} jam',
    '${minutes % 60} mnt',
  ].join(' ');
  if (remaining.isNegative || remaining == Duration.zero) {
    return 'Overdue • $duration lewat';
  }
  if (remaining <= const Duration(hours: 24)) {
    return 'Mendekati deadline • $duration tersisa';
  }
  return detail ? '$duration tersisa' : null;
}
