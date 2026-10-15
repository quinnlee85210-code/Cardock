import '../../../app/app_state.dart';
import '../../../core/calendar/calendar_reminder.dart';
import '../../../core/platform/calendar_bridge.dart';
import '../../../core/preferences/notification_privacy_preferences.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

class CalendarReminderPage extends StatefulWidget {
  const CalendarReminderPage({
    required this.state,
    required this.singleRecordId,
    super.key,
  });
  final AppState state;
  final String singleRecordId;
  @override
  State<CalendarReminderPage> createState() => _CalendarReminderPageState();
}

class _CalendarReminderPageState extends State<CalendarReminderPage> {
  NotificationPrivacy privacy = NotificationPrivacy.privacy;
  CalendarAlarm alarm = CalendarAlarm.oneDay;
  CalendarReminderPlan? plan;
  bool working = false;
  static const risk =
      '系统日历可能同步到华为、Google、Microsoft 等云账户。外部事件不再受Cardock加密保险库控制；Cardock无法删除其他应用或云端副本。修改Cardock记录不会更新外部事件，重复添加仍可能产生重复日程。';
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
    _project();
  }

  void _project() {
    try {
      plan = widget.state.projectCalendar(
        singleRecordId: widget.singleRecordId,
      );
    } on Object {
      plan = null;
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (!widget.state.isUnlocked || !widget.state.hasFullVaultAccess) {
        plan = null;
      }
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    plan = null;
    super.dispose();
  }

  Future<void> _perform() async {
    final current = plan;
    if (working || current == null || !widget.state.canOpenCalendar) return;
    final language = AppLocalizations.of(context).language;
    final l10n = AppLocalizations.of(context);
    final approved =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认打开系统日历？'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('共 {count} 个事件；提醒：{alarm}', {
                      'count': current.events.length,
                      'alarm': context.tr(alarm.label),
                    }),
                    translate: false,
                  ),
                  for (final event in current.events.take(3))
                    Text(
                      '${calendarDate(event.date)} · ${event.title(privacy, language)}',
                      translate: false,
                    ),
                  const SizedBox(height: 12),
                  const Text(risk),
                  const Text('日历应用可能忽略提醒点，请在保存界面核对。'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认继续'),
              ),
            ],
          ),
        ) ??
        false;
    if (!approved || !mounted || !widget.state.canOpenCalendar) return;
    setState(() => working = true);
    widget.state.beginExternalInteraction();
    String message;
    try {
      final result = await widget.state.insertCalendar(
        current,
        privacy: privacy,
        language: language,
        alarm: alarm,
        disclosureConfirmed: true,
      );
      message = l10n.translate(
        result == CalendarInsertResult.opened
            ? '已打开系统日历编辑界面，请核对提醒并自行保存；Cardock无法确认保存结果。'
            : '无法打开系统日历。请确认手机已安装可用的日历应用后重试。',
      );
    } finally {
      widget.state.endExternalInteraction();
    }
    if (!mounted) return;
    setState(() {
      working = false;
      privacy = NotificationPrivacy.privacy;
      alarm = CalendarAlarm.oneDay;
      _project();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message, translate: false)));
  }

  @override
  Widget build(BuildContext context) {
    final current = plan;
    final language = AppLocalizations.of(context).language;
    return Scaffold(
      appBar: AppBar(title: const Text('加入系统日历')),
      body: !widget.state.isUnlocked || !widget.state.hasFullVaultAccess
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('请完整解锁当前保险库后加入系统日历。'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(risk),
                const SizedBox(height: 16),
                const Text('本次日历内容（独立于通知隐私设置）'),
                for (final level in NotificationPrivacy.values)
                  ListTile(
                    key: ValueKey('calendar-privacy-${level.name}'),
                    minVerticalPadding: 12,
                    leading: Icon(
                      privacy == level
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(context.tr(level.label), translate: false),
                    selected: privacy == level,
                    onTap: working
                        ? null
                        : () => setState(() => privacy = level),
                  ),
                const Divider(),
                const Text('本次日历提醒'),
                for (final value in CalendarAlarm.values)
                  ListTile(
                    key: ValueKey('calendar-alarm-${value.name}'),
                    minVerticalPadding: 12,
                    leading: Icon(
                      alarm == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(context.tr(value.label), translate: false),
                    selected: alarm == value,
                    onTap: working ? null : () => setState(() => alarm = value),
                  ),
                if (current == null)
                  const Text('当前无法生成日历预览，请完整解锁后重新打开。')
                else ...[
                  Text(
                    context
                        .tr('预览：续费 {renewals}、试用 {trials}；排除 {excluded} 条记录', {
                          'renewals': current.renewalCount,
                          'trials': current.trialCount,
                          'excluded': current.excludedCount,
                        }),
                    translate: false,
                  ),
                  for (final entry in current.excluded.entries)
                    Text(
                      '${context.tr(switch (entry.key) {
                        CalendarExclusion.inactive => '已暂停、取消或结束',
                        CalendarExclusion.pastDate => '日期早于今天',
                        CalendarExclusion.conflictingDate => '续费日期与历史区间冲突',
                      })}：${entry.value}',
                      translate: false,
                    ),
                  ExpansionTile(
                    title: const Text('预览日历内容'),
                    children: [
                      for (final event in current.events)
                        ListTile(
                          title: Text(
                            event.title(privacy, language),
                            translate: false,
                          ),
                          subtitle: Text(
                            calendarDate(event.date),
                            translate: false,
                          ),
                        ),
                    ],
                  ),
                  if (current.events.isEmpty) const Text('当前记录没有可添加的有效日历日期。'),
                  FilledButton.icon(
                    key: const ValueKey('calendar-insert'),
                    onPressed:
                        working ||
                            !widget.state.canOpenCalendar ||
                            current.events.length != 1
                        ? null
                        : _perform,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('确认并打开系统日历'),
                  ),
                  const Text('日历应用可能忽略提醒点，请在保存界面核对。'),
                ],
                if (working) const LinearProgressIndicator(),
              ],
            ),
    );
  }
}
