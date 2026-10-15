import '../../features/subscriptions/domain/subscription_record.dart';
import '../preferences/language_preferences.dart';
import '../preferences/notification_privacy_preferences.dart';

/// The only subscription data allowed across notification/calendar boundaries.
/// No account, plan, note, URL, payment method or custom field is accepted.
final class SubscriptionPublicSummary {
  const SubscriptionPublicSummary({
    required this.event,
    this.serviceName,
    this.businessDate,
    this.amount,
    this.currency,
  });
  final SubscriptionReminderEvent event;
  final String? serviceName, amount, currency;
  final DateTime? businessDate;
  factory SubscriptionPublicSummary.fromSubscription(
    SubscriptionRecord s,
    SubscriptionReminderEvent event,
  ) {
    final date = event == SubscriptionReminderEvent.trialEnd
        ? s.management?.trial?.endsOn
        : s.nextRenewalOn;
    final price = date == null ? null : s.management?.priceAt(date);
    return SubscriptionPublicSummary(
      event: event,
      serviceName: s.serviceName,
      businessDate: date,
      amount: event == SubscriptionReminderEvent.trialEnd
          ? null
          : price?.amount ?? s.amount,
      currency: event == SubscriptionReminderEvent.trialEnd
          ? null
          : price?.currency ?? s.currency,
    );
  }
}

String? safeSubscriptionServiceName(String? input) {
  final value = input?.trim() ?? '';
  if (value.isEmpty ||
      value.runes.length > 100 ||
      RegExp(r'[\x00-\x1f\x7f@\u202a-\u202e\u2066-\u2069]').hasMatch(value) ||
      value.contains('://') ||
      RegExp(r'^\+?[\d ()-]{7,}$').hasMatch(value)) {
    return null;
  }
  return value;
}

({String title, String body}) subscriptionNotificationContent({
  required SubscriptionPublicSummary summary,
  required NotificationPrivacy privacy,
  required CardockLanguage language,
  int count = 1,
}) {
  String tr(String zh, String en, String ja) => switch (language) {
    CardockLanguage.simplifiedChinese => zh,
    CardockLanguage.english => en,
    CardockLanguage.japanese => ja,
  };
  final title = tr('订阅提醒', 'Subscription reminder', 'サブスクリプション通知');
  if (count > 1) {
    return (
      title: title,
      body: tr(
        '有 $count 项订阅事项需要查看，请解锁应用确认。',
        '$count subscription items need attention. Unlock the app to review.',
        '$count 件のサブスクリプション事項があります。アプリをロック解除して確認してください。',
      ),
    );
  }
  final event = switch (summary.event) {
    SubscriptionReminderEvent.renewal => tr(
      '即将续费',
      'Renewal approaching',
      '更新日が近づいています',
    ),
    SubscriptionReminderEvent.trialEnd => tr(
      '试用即将结束',
      'Trial ending soon',
      '試用期間がまもなく終了します',
    ),
    SubscriptionReminderEvent.decision => tr(
      '有订阅事项需要处理',
      'Subscription decision needed',
      'サブスクリプションの確認が必要です',
    ),
  };
  final service = safeSubscriptionServiceName(summary.serviceName);
  if (privacy == NotificationPrivacy.privacy || service == null) {
    return (
      title: title,
      body: '${tr('订阅事项', 'Subscription', 'サブスクリプション')} · $event',
    );
  }
  final parts = <String>[service, event];
  if (privacy == NotificationPrivacy.fullSummary) {
    if (summary.businessDate case final date?) {
      parts.add(formatSubscriptionDate(date));
    }
    final amount = summary.amount, currency = summary.currency;
    if (amount != null &&
        currency != null &&
        RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(amount) &&
        RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      parts.add('$currency $amount');
    }
  }
  return (title: title, body: parts.join(' · '));
}
