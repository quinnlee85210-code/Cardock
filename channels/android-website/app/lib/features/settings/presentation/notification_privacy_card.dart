import '../../../app/app_state.dart';
import '../../../core/preferences/notification_privacy_preferences.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

class NotificationPrivacyCard extends StatelessWidget {
  const NotificationPrivacyCard({required this.state, super.key});
  final AppState state;
  static const risk =
      '服务名称、日期和金额可能出现在锁屏、通知历史、手表或系统同步中，并在切回隐私模式后继续保留。账号、密码和备注永远不会进入通知。';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('通知内容隐私', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('默认仅显示通用事项；同一时刻的多项同类提醒始终合并为通用数量摘要。'),
            if (!state.canChangeNotificationPrivacy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('仅在真实保险库完整解锁且空闲时可修改；诱饵库和订阅只读视图不可修改。'),
              ),
            for (final level in NotificationPrivacy.values)
              ListTile(
                key: ValueKey('notification-privacy-${level.name}'),
                dense: true,
                minTileHeight: 48,
                minVerticalPadding: 4,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                horizontalTitleGap: 8,
                minLeadingWidth: 24,
                leading: Icon(
                  state.notificationPrivacy == level
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(context.tr(level.label), translate: false),
                selected: state.notificationPrivacy == level,
                enabled: state.canChangeNotificationPrivacy,
                onTap: state.canChangeNotificationPrivacy
                    ? () => _change(context, level)
                    : null,
              ),
            const Text('切回隐私模式会重排待发提醒，但无法删除其他设备或系统已经保留的通知副本。'),
          ],
        ),
      ),
    ),
  );
  Future<void> _change(BuildContext context, NotificationPrivacy level) async {
    var confirmed = false;
    if (level.index > state.notificationPrivacy.index) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('允许通知显示订阅信息？'),
              content: const SingleChildScrollView(child: Text(risk)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认显示'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }
    final saved = await state.setNotificationPrivacy(
      level,
      riskConfirmed: confirmed,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? '通知隐私设置已保存；待发提醒按当前设置重新协调。' : '通知隐私设置未完成，请重试；业务数据未改变。',
        ),
      ),
    );
  }
}
