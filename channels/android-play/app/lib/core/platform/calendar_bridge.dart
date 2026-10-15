import 'package:flutter/services.dart';
import '../calendar/calendar_reminder.dart';
import '../preferences/language_preferences.dart';
import '../preferences/notification_privacy_preferences.dart';

enum CalendarInsertResult { opened, unavailable, failed }

abstract interface class CalendarBridge {
  Future<CalendarInsertResult> insert(
    CalendarEventProjection event, {
    required NotificationPrivacy privacy,
    required CardockLanguage language,
    required CalendarAlarm alarm,
  });
}

final class AndroidCalendarBridge implements CalendarBridge {
  const AndroidCalendarBridge();
  static const channel = MethodChannel('cardock/calendar_insert_v1');
  @override
  Future<CalendarInsertResult> insert(
    CalendarEventProjection event, {
    required NotificationPrivacy privacy,
    required CardockLanguage language,
    required CalendarAlarm alarm,
  }) async {
    try {
      final result = await channel.invokeMethod<String>('insert', {
        'title': event.title(privacy, language),
        'begin': DateTime.utc(
          event.date.year,
          event.date.month,
          event.date.day,
        ).millisecondsSinceEpoch,
        'end': DateTime.utc(
          event.date.year,
          event.date.month,
          event.date.day + 1,
        ).millisecondsSinceEpoch,
        'alarmDays': alarm.days,
      });
      return result == 'opened'
          ? CalendarInsertResult.opened
          : CalendarInsertResult.unavailable;
    } on Object {
      return CalendarInsertResult.failed;
    }
  }
}
