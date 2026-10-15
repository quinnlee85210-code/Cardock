import 'dart:async';
import '../../../app/app_state.dart';
import '../../../core/storage/vault_rebuild_service.dart';
import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../settings/presentation/data_safety_dialogs.dart';

class VaultRebuildPage extends StatefulWidget {
  const VaultRebuildPage({required this.appState, this.onRecovery, super.key});
  final AppState appState;
  final VoidCallback? onRecovery;
  @override
  State<VaultRebuildPage> createState() => _VaultRebuildPageState();
}

class _VaultRebuildPageState extends State<VaultRebuildPage> {
  RebuildAuthorization? authorization;
  String phrase = '', second = '';
  bool working = false, holdReady = false, pointerHeld = false;
  int holdEpoch = 0;
  Timer? hold;
  @override
  void dispose() {
    hold?.cancel();
    super.dispose();
  }

  Future<void> authenticate() async {
    if (!await safetyConfirm(
      context,
      '删除本机 Cardock 数据并重新开始',
      '此操作不会找回旧密码，也不会解密旧数据；没有可用备份的数据将永久丢失。外部 .asmbackup 文件和合法完整版授权会保留。恢复备份仍需对应备份密码。',
    )) {
      return;
    }
    if (!mounted) return;
    widget.appState.beginExternalInteraction();
    RebuildAuthorization? result;
    try {
      result = await widget.appState.authorizeRebuild(
        context.tr('验证设备身份'),
        context.tr('确认删除本机 Cardock 数据'),
      );
    } finally {
      widget.appState.endExternalInteraction();
    }
    if (mounted) setState(() => authorization = result);
  }

  Future<void> commit() async {
    final auth = authorization;
    if (auth == null ||
        phrase != '删除本机 Cardock 数据' ||
        (auth.unsecured && (second != '我理解没有备份将无法恢复' || !holdReady))) {
      return;
    }
    if (!await safetyConfirm(
      context,
      '最终确认：删除本机数据？',
      '删除后无法撤销。外部备份文件不会删除。',
      action: '删除并重新开始',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => working = true);
    final ok = await widget.appState.rebuildLocalVault(
      authorization: auth,
      phrase: phrase,
      secondPhrase: second,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() {
        working = false;
        authorization = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('重建未完成；若清理已开始，请重新打开应用继续完成。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = authorization;
    return PopScope(
      canPop: !working,
      child: Scaffold(
        appBar: AppBar(title: const Text('忘记密码或重新开始')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('请选择下一步。找回访问不会显示旧密码；删除本机数据无法撤销。'),
            const SizedBox(height: 16),
            Card(
              key: const ValueKey<String>('vault-recovery-option'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.security_rounded),
                      title: Text('通过密保重设保险库密码'),
                      subtitle: Text('旧密码不会被找回或显示；必须选对预设的三道问题，并通过本机指纹或安全级人脸。'),
                    ),
                    FilledButton(
                      key: const ValueKey<String>(
                        'start-vault-recovery-option',
                      ),
                      onPressed: working ? null : widget.onRecovery,
                      child: Text(
                        widget.onRecovery == null
                            ? '当前入口没有可用的密码恢复配置'
                            : '选择密保找回访问',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              key: const ValueKey<String>('vault-rebuild-option'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_forever_outlined),
                      title: Text('删除本机数据并重新开始'),
                      subtitle: Text(
                        '之后可创建新保险库，再从外部 .asmbackup 文件恢复其中的真实库记录；独立诱饵库不会随真实库备份恢复，且仍需对应备份密码。',
                      ),
                    ),
                    const Text(
                      '真实库、诱饵库、回收站、本地恢复凭据、自动备份配置和临时录入资料都会清除。外部备份不会删除。',
                    ),
                    const SizedBox(height: 16),
                    if (auth == null)
                      FilledButton(
                        onPressed: working ? null : authenticate,
                        child: const Text('了解后验证设备身份'),
                      ),
                    if (auth != null) ...[
                      if (auth.unsecured)
                        const Text('设备未设置系统锁屏凭据。必须完成双重文字确认，并按住按钮至少 3 秒。'),
                      TextField(
                        onChanged: (value) => setState(() => phrase = value),
                        enabled: !working,
                        decoration: InputDecoration(
                          labelText: context.tr('输入“删除本机 Cardock 数据”'),
                        ),
                      ),
                      if (auth.unsecured) ...[
                        TextField(
                          onChanged: (value) => setState(() => second = value),
                          enabled: !working,
                          decoration: InputDecoration(
                            labelText: context.tr('输入“我理解没有备份将无法恢复”'),
                          ),
                        ),
                        Listener(
                          onPointerDown: (_) async {
                            final epoch = ++holdEpoch;
                            pointerHeld = true;
                            holdReady = false;
                            hold?.cancel();
                            await widget.appState.beginRebuildHold(auth);
                            if (!mounted ||
                                !pointerHeld ||
                                epoch != holdEpoch) {
                              widget.appState.cancelRebuildHold(auth);
                              return;
                            }
                            hold = Timer(
                              const Duration(milliseconds: 3200),
                              () {
                                if (mounted &&
                                    pointerHeld &&
                                    epoch == holdEpoch) {
                                  setState(() => holdReady = true);
                                }
                              },
                            );
                          },
                          onPointerUp: (_) {
                            pointerHeld = false;
                            holdEpoch++;
                            hold?.cancel();
                            if (!holdReady) {
                              widget.appState.cancelRebuildHold(auth);
                            }
                          },
                          onPointerCancel: (_) {
                            pointerHeld = false;
                            holdEpoch++;
                            hold?.cancel();
                            holdReady = false;
                            widget.appState.cancelRebuildHold(auth);
                          },
                          child: OutlinedButton(
                            onPressed: () {},
                            child: Text(holdReady ? '长按确认已完成' : '按住至少 3 秒'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed:
                            working ||
                                phrase != '删除本机 Cardock 数据' ||
                                (auth.unsecured &&
                                    (!holdReady || second != '我理解没有备份将无法恢复'))
                            ? null
                            : commit,
                        child: const Text('删除并重新开始'),
                      ),
                    ],
                    if (working) ...[
                      const LinearProgressIndicator(),
                      const Text('正在重建，请稍候…'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
