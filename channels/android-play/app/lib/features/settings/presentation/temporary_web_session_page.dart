import 'dart:async';

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';

import '../../../core/platform/sensitive_clipboard.dart';
import '../../../core/temporary_web/temporary_web_controller.dart';
import '../../../core/temporary_web/temporary_web_models.dart';
import '../../../core/theme/cardock_tokens.dart';
import '../../../shared/widgets/cardock_ui.dart';

class TemporaryWebSessionPage extends StatefulWidget {
  const TemporaryWebSessionPage({
    required this.controller,
    this.sensitiveClipboard = const PlatformSensitiveClipboard(),
    super.key,
  });

  final TemporaryWebSessionController controller;
  final SensitiveClipboard sensitiveClipboard;

  @override
  State<TemporaryWebSessionPage> createState() =>
      _TemporaryWebSessionPageState();
}

class _TemporaryWebSessionPageState extends State<TemporaryWebSessionPage> {
  List<TemporaryWebAddress> _addresses = const <TemporaryWebAddress>[];
  TemporaryWebAddress? _selectedAddress;
  TemporaryWebHistoryMode _historyMode =
      TemporaryWebHistoryMode.currentSessionOnly;
  Duration _connectionDuration = const Duration(minutes: 5);
  bool _allowHistoryEditing = false;
  bool _allowHistoricalPasswordReveal = false;
  bool _loadingAddresses = true;
  bool _working = false;
  String? _localError;
  String? _approvalInProgress;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.controller.snapshot.isRunning) setState(() {});
    });
    unawaited(_reloadAddresses());
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _reloadAddresses() async {
    if (widget.controller.snapshot.isRunning) return;
    setState(() {
      _loadingAddresses = true;
      _localError = null;
    });
    try {
      final addresses = await widget.controller.listAddresses();
      if (!mounted) return;
      final previous = _selectedAddress?.address;
      setState(() {
        _addresses = addresses;
        _selectedAddress = addresses
            .where((item) => item.address == previous)
            .firstOrNull;
        _selectedAddress ??= addresses.firstOrNull;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _localError = context.tr('读取局域网地址失败：{error}', <String, Object?>{
            'error': _safeError(error),
          }),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAddresses = false);
    }
  }

  Future<void> _start() async {
    final address = _selectedAddress;
    if (_working || address == null || !widget.controller.canStart) return;
    setState(() {
      _working = true;
      _localError = null;
    });
    try {
      await widget.controller.start(
        address: address,
        policy: TemporaryWebSessionPolicy(
          historyMode: _historyMode,
          allowHistoryEditing: _allowHistoryEditing,
          allowHistoricalPasswordReveal: _allowHistoricalPasswordReveal,
          connectionDuration: _connectionDuration,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        final controllerMessage = widget.controller.snapshot.errorMessage;
        setState(
          () => _localError =
              controllerMessage ?? _temporaryWebStartErrorMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _disconnect() async {
    if (_working || !widget.controller.snapshot.isRunning) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('断开电脑网页？'),
            content: const Text('断开后网页会立即失效，本次连接保存的记录会立刻按历史记录处理；以后再删除时需要手机确认。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续连接'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('断开'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !widget.controller.snapshot.isRunning) return;
    widget.controller.stop(TemporaryWebStopReason.user);
  }

  Future<void> _copyConnectionCode(String code) async {
    try {
      await widget.sensitiveClipboard.copySensitive(
        text: code,
        label: context.tr('一次性连接码'),
        clearAfter: const Duration(seconds: 60),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(context.tr('连接码已复制；系统将在 60 秒后尽力清理剪贴板。'))),
        );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.tr('连接码复制失败，请手动输入。'))));
    }
  }

  Future<void> _approve(TemporaryWebApproval approval) async {
    if (_approvalInProgress != null) return;
    setState(() => _approvalInProgress = approval.id);
    try {
      await widget.controller.approve(approval.id);
    } finally {
      if (mounted) {
        setState(() => _approvalInProgress = null);
      }
    }
  }

  void _reject(TemporaryWebApproval approval) {
    if (_approvalInProgress != null) return;
    unawaited(widget.controller.reject(approval.id));
  }

  void _setHistoryMode(TemporaryWebHistoryMode mode) {
    if (_working || widget.controller.snapshot.isRunning) return;
    setState(() {
      _historyMode = mode;
      if (mode != TemporaryWebHistoryMode.details) {
        _allowHistoryEditing = false;
      }
      if (mode == TemporaryWebHistoryMode.currentSessionOnly) {
        _allowHistoricalPasswordReveal = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('电脑临时录入')),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) {
          final snapshot = widget.controller.snapshot;
          final stoppedError = snapshot.isRunning
              ? null
              : snapshot.errorMessage;
          final stoppedReason = snapshot.isRunning || stoppedError != null
              ? null
              : snapshot.stopReason;
          return ListView(
            key: const ValueKey<String>('temporary-web-session-page'),
            padding: const EdgeInsets.fromLTRB(
              CardockLayout.screenHorizontal,
              8,
              CardockLayout.screenHorizontal,
              32,
            ),
            children: [
              const _TrustedNetworkNotice(),
              const SizedBox(height: 18),
              if (snapshot.isRunning)
                _RunningSessionCard(
                  snapshot: snapshot,
                  remaining: widget.controller.connectionRemaining,
                  onCopyCode: _copyConnectionCode,
                  onDisconnect: _working ? null : _disconnect,
                )
              else ...[
                _AddressSection(
                  addresses: _addresses,
                  selectedAddress: _selectedAddress,
                  loading: _loadingAddresses,
                  onChanged: _working
                      ? null
                      : (value) => setState(() => _selectedAddress = value),
                  onReload: _working ? null : _reloadAddresses,
                ),
                const SizedBox(height: 18),
                _HistorySection(
                  mode: _historyMode,
                  allowHistoryEditing: _allowHistoryEditing,
                  allowHistoricalPasswordReveal: _allowHistoricalPasswordReveal,
                  enabled: !_working,
                  onModeChanged: _setHistoryMode,
                  onHistoryEditingChanged:
                      _historyMode == TemporaryWebHistoryMode.details
                      ? (value) => setState(() => _allowHistoryEditing = value)
                      : null,
                  onHistoricalPasswordRevealChanged:
                      _historyMode != TemporaryWebHistoryMode.currentSessionOnly
                      ? (value) => setState(
                          () => _allowHistoricalPasswordReveal = value,
                        )
                      : null,
                ),
                const SizedBox(height: 18),
                _TimeoutSection(
                  selected: _connectionDuration,
                  enabled: !_working,
                  onChanged: (value) =>
                      setState(() => _connectionDuration = value),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey<String>('temporary-web-start'),
                  onPressed:
                      _working ||
                          _selectedAddress == null ||
                          !widget.controller.canStart
                      ? null
                      : _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(_working ? '正在开启…' : '开启本次临时连接'),
                ),
                if (!widget.controller.canStart && !_working)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '仅真实保险库完整解锁且当前无其他写入时可开启；诱饵库和“仅查看订阅”模式不能开启。',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
              if (_localError case final error?) ...[
                const SizedBox(height: 14),
                _ErrorCard(message: error),
              ] else if (stoppedError case final error?) ...[
                const SizedBox(height: 14),
                _ErrorCard(message: error),
              ] else if (stoppedReason case final reason?) ...[
                const SizedBox(height: 14),
                _EndedCard(reason: reason),
              ],
              if (snapshot.isRunning &&
                  snapshot.pendingApprovals.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('等待手机确认', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                for (final approval in snapshot.pendingApprovals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ApprovalCard(
                      approval: approval,
                      remaining: widget.controller.approvalRemaining(approval),
                      working: _approvalInProgress == approval.id,
                      actionsEnabled: _approvalInProgress == null,
                      onApprove: () => _approve(approval),
                      onReject: () => _reject(approval),
                    ),
                  ),
              ],
              if (_working) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TrustedNetworkNotice extends StatelessWidget {
  const _TrustedNetworkNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = context.cardockTheme.palette;
    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardockSemanticIcon(
              icon: Icons.wifi_lock_outlined,
              color: palette.statusInformation,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '仅在你自己的手机热点或可信私有无线网络使用。应用不会访问公网、云或中继；不要在公共或陌生 Wi-Fi 开启。\n\n'
                '连接前建议先在电脑打开浏览器无痕/隐私窗口，以减少常规浏览记录和站点数据残留；无痕模式仍不能保证电脑绝对不留痕。\n\n'
                '普通锁屏、返回 Home、切换应用或接听来电时，电脑连接会继续保留；Android 会显示一条不含账号、密码或订阅内容的低敏前台服务通知。\n\n'
                '保险库锁定后，电脑仍可继续填写尚未提交的内容；保存或导入会暂停，需回到卡坞并解锁手机后继续。\n\n'
                '只要应用进程仍在，正常使用中仅手机主动断开或所选连接时间到达会结束；划掉卡坞、强制停止、应用进程死亡或手机关机会使服务自然不可用。',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({
    required this.addresses,
    required this.selectedAddress,
    required this.loading,
    required this.onChanged,
    required this.onReload,
  });

  final List<TemporaryWebAddress> addresses;
  final TemporaryWebAddress? selectedAddress;
  final bool loading;
  final ValueChanged<TemporaryWebAddress?>? onChanged;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('连接地址', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (loading)
          const LinearProgressIndicator()
        else if (addresses.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.wifi_off_outlined),
              title: const Text('没有可用的可信局域网地址'),
              subtitle: const Text('请先打开手机热点，或让手机与电脑连接同一个无线网络。'),
              trailing: IconButton(
                onPressed: onReload,
                tooltip: context.tr('重新检测'),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
          )
        else
          DropdownButtonFormField<TemporaryWebAddress>(
            key: const ValueKey<String>('temporary-web-address'),
            initialValue: selectedAddress,
            decoration: InputDecoration(
              labelText: context.tr('手机局域网 IP'),
              helperText: context.tr('开启后会自动分配临时端口'),
            ),
            items: [
              for (final address in addresses)
                DropdownMenuItem<TemporaryWebAddress>(
                  value: address,
                  child: Text(
                    address.label,
                    translate: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.mode,
    required this.allowHistoryEditing,
    required this.allowHistoricalPasswordReveal,
    required this.enabled,
    required this.onModeChanged,
    required this.onHistoryEditingChanged,
    required this.onHistoricalPasswordRevealChanged,
  });

  final TemporaryWebHistoryMode mode;
  final bool allowHistoryEditing;
  final bool allowHistoricalPasswordReveal;
  final bool enabled;
  final ValueChanged<TemporaryWebHistoryMode> onModeChanged;
  final ValueChanged<bool>? onHistoryEditingChanged;
  final ValueChanged<bool>? onHistoricalPasswordRevealChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('网页可见范围', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: RadioGroup<TemporaryWebHistoryMode>(
            groupValue: mode,
            onChanged: (value) {
              if (enabled && value != null) onModeChanged(value);
            },
            child: Column(
              children: [
                for (final item in TemporaryWebHistoryMode.values)
                  RadioListTile<TemporaryWebHistoryMode>(
                    key: ValueKey<String>('temporary-web-history-${item.name}'),
                    title: Text(item.label),
                    subtitle: Text(_historyDescription(item)),
                    value: item,
                    enabled: enabled,
                  ),
                const Divider(height: 1),
                SwitchListTile(
                  key: const ValueKey<String>('temporary-web-history-edit'),
                  secondary: const Icon(Icons.edit_outlined),
                  title: const Text('允许编辑历史记录'),
                  subtitle: const Text('仅“历史详情”可开启；删除历史记录仍须手机逐次确认'),
                  value: allowHistoryEditing,
                  onChanged: enabled ? onHistoryEditingChanged : null,
                ),
                SwitchListTile(
                  key: const ValueKey<String>('temporary-web-password-reveal'),
                  secondary: const Icon(Icons.password_outlined),
                  title: const Text('允许申请查看旧密码'),
                  subtitle: const Text('每次仍须手机确认；网页只显示 30 秒'),
                  value: allowHistoricalPasswordReveal,
                  onChanged: enabled ? onHistoricalPasswordRevealChanged : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _historyDescription(TemporaryWebHistoryMode mode) =>
      switch (mode) {
        TemporaryWebHistoryMode.currentSessionOnly => '只显示这次连接新建的记录（推荐）',
        TemporaryWebHistoryMode.summary => '显示名称、分类、续费日期等摘要，不显示详情',
        TemporaryWebHistoryMode.details => '显示历史详情，但旧密码仍默认隐藏',
      };
}

class _TimeoutSection extends StatelessWidget {
  const _TimeoutSection({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final Duration selected;
  final bool enabled;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('连接时间', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        DropdownButtonFormField<Duration>(
          key: const ValueKey<String>('temporary-web-connection-duration'),
          initialValue: selected,
          decoration: InputDecoration(
            labelText: context.tr('本次连接持续时间'),
            helperText: context.tr('可选 1/5/10/30 分钟，默认 5 分钟；从开启服务时开始计时'),
          ),
          items: [
            for (final timeout
                in TemporaryWebSessionPolicy.allowedConnectionDurations)
              DropdownMenuItem<Duration>(
                value: timeout,
                child: Text(
                  context.tr('{minutes} 分钟', <String, Object?>{
                    'minutes': timeout.inMinutes,
                  }),
                ),
              ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onChanged(value);
                }
              : null,
        ),
      ],
    );
  }
}

class _RunningSessionCard extends StatelessWidget {
  const _RunningSessionCard({
    required this.snapshot,
    required this.remaining,
    required this.onCopyCode,
    required this.onDisconnect,
  });

  final TemporaryWebSessionSnapshot snapshot;
  final Duration remaining;
  final ValueChanged<String> onCopyCode;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final browserUri = snapshot.browserUri;
    final code = snapshot.formattedConnectionCode;
    return Card(
      key: const ValueKey<String>('temporary-web-running'),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  snapshot.phase == TemporaryWebSessionPhase.connected
                      ? Icons.laptop_chromebook_rounded
                      : Icons.wifi_tethering_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr(_phaseLabel(snapshot)),
                    translate: false,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('在电脑浏览器地址栏输入（无需输入 http://）'),
            const SizedBox(height: 4),
            SelectableText(
              browserUri?.authority ?? '正在分配地址…',
              key: const ValueKey<String>('temporary-web-url'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (code != null) ...[
              const SizedBox(height: 18),
              const Text('一次性连接码'),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: SelectableText(
                      code,
                      key: const ValueKey<String>('temporary-web-code'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey<String>('temporary-web-copy-code'),
                    onPressed: () => onCopyCode(code),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('复制'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('直接在网页输入；不使用二维码。连接成功后本码立即失效。'),
            ],
            if (snapshot.connectedClientAddress case final client?) ...[
              const SizedBox(height: 14),
              Text(
                context.tr('已连接电脑：{client}', <String, Object?>{
                  'client': client,
                }),
                translate: false,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('手机锁屏、Home 或切到后台不会主动结束连接；需要立即结束请点“主动断开”。'),
                translate: false,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Divider(height: 28),
            Text(
              context.tr('本次连接还剩 {remaining}，到时自动断开', <String, Object?>{
                'remaining': _formatDuration(remaining),
              }),
              translate: false,
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('{mode} · {editing} · {passwords}', <String, Object?>{
                'mode': context.tr(snapshot.policy.historyMode.label),
                'editing': context.tr(
                  snapshot.policy.allowHistoryEditing ? '允许历史编辑' : '历史编辑关闭',
                ),
                'passwords': context.tr(
                  snapshot.policy.allowHistoricalPasswordReveal
                      ? '可申请旧密码'
                      : '旧密码关闭',
                ),
              }),
              translate: false,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey<String>('temporary-web-disconnect'),
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('主动断开'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(TemporaryWebSessionSnapshot snapshot) =>
      switch (snapshot.phase) {
        TemporaryWebSessionPhase.starting => '正在开启临时服务',
        TemporaryWebSessionPhase.waitingForPairing => '等待电脑输入连接码',
        TemporaryWebSessionPhase.connected => '电脑网页已连接',
        TemporaryWebSessionPhase.stopped => '会话已结束',
      };
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.approval,
    required this.remaining,
    required this.working,
    required this.actionsEnabled,
    required this.onApprove,
    required this.onReject,
  });

  final TemporaryWebApproval approval;
  final Duration remaining;
  final bool working;
  final bool actionsEnabled;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(approval.title),
              translate: false,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                approval.detailTranslationKey ?? approval.detail,
                approval.detailTranslationValues,
              ),
              translate: false,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('确认将在 {duration} 后失效', <String, Object?>{
                'duration': _formatDuration(remaining),
              }),
              translate: false,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: actionsEnabled ? onReject : null,
                  child: const Text('拒绝'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: actionsEnabled ? onApprove : null,
                  child: Text(
                    working
                        ? '处理中…'
                        : approval.duplicateConfirmationRequired
                        ? '仍然新增'
                        : '批准本次操作',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EndedCard extends StatelessWidget {
  const _EndedCard({required this.reason});

  final TemporaryWebStopReason reason;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.link_off_rounded),
      title: const Text('上次临时连接已结束'),
      subtitle: Text(context.tr(_stopReasonLabel(reason)), translate: false),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.error_outline_rounded),
      title: const Text('临时连接未能继续'),
      subtitle: Text(context.tr(message), translate: false),
    ),
  );
}

String _formatDuration(Duration value) {
  final seconds = value.inSeconds.clamp(0, 99 * 60 + 59);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

String _stopReasonLabel(TemporaryWebStopReason reason) => switch (reason) {
  TemporaryWebStopReason.user => '已由手机或电脑主动断开。',
  TemporaryWebStopReason.idleTimeout => '已达到所选连接时长。',
  TemporaryWebStopReason.absoluteTimeout => '已达到所选连接时长。',
  TemporaryWebStopReason.phoneLocked => '手机保险库已锁定。',
  TemporaryWebStopReason.appBackgrounded => '应用进程已退出或被系统终止，连接已结束。',
  TemporaryWebStopReason.vaultChanged => '手机保险库状态发生变化，为保护数据已断开。',
  TemporaryWebStopReason.networkChanged => '局域网地址发生变化，已断开。',
  TemporaryWebStopReason.browserDisconnected => '电脑网页心跳已失联，页面记录已立即转为历史记录。',
  TemporaryWebStopReason.pairingRejected => '连接码验证失败，本次服务已失效。',
  TemporaryWebStopReason.transportFailure => '局域网服务发生异常。',
  TemporaryWebStopReason.disposed => '应用已关闭临时服务。',
};

String _safeError(Object error) {
  final text = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  return text.length <= 180 ? text : '${text.substring(0, 180)}…';
}

String _temporaryWebStartErrorMessage(Object error) {
  final detail = _safeError(error);
  const knownMessages = <String>[
    '当前保险库状态不允许开启电脑临时录入。',
    '网页空闲时限必须为 1、5、10 或 30 分钟。',
    '所选局域网地址已不可用，请重新选择。',
  ];
  for (final message in knownMessages) {
    if (detail.contains(message)) return message;
  }
  return '局域网临时服务启动失败：$detail';
}
