import 'dart:typed_data';
import '../../../core/platform/import_document_picker.dart';
import '../../../core/storage/data_transfer_file_classifier.dart';

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import 'data_import_ui_controller.dart';

typedef DataImportDocumentPicker =
    Future<({String name, Uint8List bytes})?> Function();

class DataMigrationCenterPage extends StatefulWidget {
  const DataMigrationCenterPage({
    required this.controller,
    this.ownsController = true,
    this.pendingDraftCount = 0,
    this.onOpenPendingSubscriptions,
    this.documentPicker = pickImportDocument,
    super.key,
  });

  final DataImportUiController controller;
  final bool ownsController;
  final int pendingDraftCount;
  final Future<void> Function()? onOpenPendingSubscriptions;
  final DataImportDocumentPicker documentPicker;

  @override
  State<DataMigrationCenterPage> createState() =>
      _DataMigrationCenterPageState();
}

class _DataMigrationCenterPageState extends State<DataMigrationCenterPage>
    with WidgetsBindingObserver {
  static const int _maximumFileBytes = 10 * 1024 * 1024;

  DataImportUiController get _controller => widget.controller;
  bool _systemDocumentPickerActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant DataMigrationCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onChanged);
    if (oldWidget.ownsController) {
      oldWidget.controller
        ..clearSensitiveMemory()
        ..dispose();
    }
    _controller.addListener(_onChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_systemDocumentPickerActive) {
      _controller.clearSensitiveMemory();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.clearSensitiveMemory();
    if (widget.ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFile({
    bool append = false,
    bool customFields = false,
  }) async {
    if (!_controller.state.canWrite || _controller.state.working) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开导入文件前确认'),
        content: const Text(
          'XLSX、DOCX、CSV、TSV 或 TXT 文件可能包含明文密码。请仅在可信设备操作，不要发送到聊天或公共网盘。解析只在本次内存中进行；导入与加密备份核对后，请自行处理源文件。备份仅保护已导入的记录，不会保护或删除外部 CSV 及其他副本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续选择文件'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final ({String name, Uint8List bytes})? file;
    _systemDocumentPickerActive = true;
    try {
      file = await widget.documentPicker();
    } on Object {
      _showMessage('无法读取所选文件，请重新选择。');
      return;
    } finally {
      _systemDocumentPickerActive = false;
    }
    if (file == null) return;
    final bytes = file.bytes;
    if (!mounted) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    final rejectionMessage = switch (classifyDataTransferFile(
      fileName: file.name,
      bytes: bytes,
    )) {
      DataTransferFileRole.externalImport => null,
      DataTransferFileRole.encryptedBackup =>
        '这是 Cardock 加密备份。请返回设置并使用“恢复 Cardock 加密备份”；此处只导入外部表格或文档。',
      DataTransferFileRole.calendarIcs =>
        '这是日历 .ics 文件，只包含日历事件，不是账号与订阅备份，不能在这里恢复。',
      DataTransferFileRole.unsupported =>
        '不支持此文件；这里只能导入 XLSX、DOCX、CSV、TSV 或 TXT。',
    };
    if (rejectionMessage != null) {
      bytes.fillRange(0, bytes.length, 0);
      _showMessage(rejectionMessage);
      return;
    }
    if (bytes.length > _maximumFileBytes) {
      bytes.fillRange(0, bytes.length, 0);
      _showMessage('文件不能超过 10 MiB。');
      return;
    }
    try {
      final bool loaded;
      if (customFields) {
        loaded = await _controller.loadCustomFieldFile(
          fileName: file.name,
          bytes: bytes,
        );
      } else if (append) {
        loaded = await _controller.appendFile(
          fileName: file.name,
          bytes: bytes,
        );
      } else {
        loaded = await _controller.loadFile(fileName: file.name, bytes: bytes);
      }
      if (mounted && loaded) {
        _showMessage(
          customFields
              ? '自定义字段文件已读取；请继续核对字段。'
              : append
              ? '配套文件已读取；请点击“下一步”核对字段。'
              : '文件已读取；可追加配套表，或点击“下一步”核对字段。',
        );
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(message))));
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) _controller.clearSensitiveMemory();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(
            context,
          ).scale(56).clamp(56, 96).toDouble(),
          title: const Text(
            '外部数据导入',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _ProgressHeader(step: state.step),
              if (!state.canWrite)
                const _WriteDisabledNotice()
              else if (state.errorMessage case final error?)
                _ErrorNotice(message: error),
              if (state.sourceMismatch)
                TextButton(
                  onPressed: state.working
                      ? null
                      : _controller.useGenericMapping,
                  child: const Text('改用通用映射'),
                ),
              if (state.working && state.parseProgress != null)
                _ParsingNotice(
                  progress: state.parseProgress,
                  onCancel: _controller.cancelParsing,
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey<DataImportWizardStep>(state.step),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stepBody(state),
                          if (state.step == DataImportWizardStep.mapping ||
                              state.step ==
                                  DataImportWizardStep.duplicates) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: state.working
                                  ? null
                                  : () => _pickFile(customFields: true),
                              icon: const Icon(Icons.playlist_add),
                              label: const Text('添加 Cardock 自定义字段伴随文件'),
                            ),
                            const Text(
                              'account_key 必须唯一关联同一计划的 Cardock 账号模板。最多 10 个字段；同名默认保留现有值。',
                            ),
                            for (final field in state.customFields)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        '${field.accountKey} · ${field.name} · ${field.typeCode}',
                                        translate: false,
                                      ),
                                      Text(
                                        field.displayValue.isEmpty
                                            ? context.tr('未填写')
                                            : field.displayValue,
                                        translate: false,
                                      ),
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          field.sensitive
                                              ? '我明确确认导入此敏感字段值'
                                              : '导入此字段',
                                        ),
                                        value: field.included,
                                        onChanged: (value) =>
                                            _controller.setCustomFieldDecision(
                                              field.rowNumber,
                                              include: value ?? false,
                                              replaceExisting:
                                                  field.replaceExisting,
                                              sensitiveConfirmed:
                                                  field.sensitive &&
                                                  (value ?? false),
                                            ),
                                      ),
                                      if (field.conflict)
                                        SwitchListTile(
                                          contentPadding: EdgeInsets.zero,
                                          title: const Text('替换现有同名字段'),
                                          subtitle: const Text(
                                            '默认保留现有值；此选择只影响这一项。',
                                          ),
                                          value: field.replaceExisting,
                                          onChanged: (value) => _controller
                                              .setCustomFieldDecision(
                                                field.rowNumber,
                                                include: field.included,
                                                replaceExisting: value,
                                                sensitiveConfirmed:
                                                    field.confirmed,
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (state.step != DataImportWizardStep.result)
                _WizardActions(
                  state: state,
                  onBack: state.working ? null : _controller.back,
                  onNext: state.working || !state.canWrite
                      ? null
                      : state.step == DataImportWizardStep.confirmation
                      ? _controller.commit
                      : _controller.next,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepBody(DataImportUiState state) => switch (state.step) {
    DataImportWizardStep.source => _SourceStep(
      sources: _controller.sources,
      selectedSourceId: state.selectedSourceId,
      onSelected: state.working ? null : _controller.selectSource,
    ),
    DataImportWizardStep.file => _FileStep(
      state: state,
      onPick: () => _pickFile(),
      onAppend: () => _pickFile(append: true),
    ),
    DataImportWizardStep.mapping => _MappingStep(
      state: state,
      onAcceptSuggestion: _controller.acceptFieldSuggestion,
      onAcceptAllSuggestions: _controller.acceptAllFieldSuggestions,
      onIgnoreAllSuggestions: _controller.ignoreAllFieldSuggestions,
      onChanged: ({required columnIndex, required targetField}) => _controller
          .updateMapping(columnIndex: columnIndex, targetField: targetField),
    ),
    DataImportWizardStep.passwordPreview => _PasswordPreviewStep(
      state: state,
      onMaskedPasswordConfirmed: _controller.setMaskedPasswordConfirmed,
      onBrandSelected: _controller.selectBrandSuggestion,
      onBrandIgnored: _controller.ignoreBrandSuggestions,
    ),
    DataImportWizardStep.duplicates => _DuplicateStep(
      state: state,
      onSelected: _controller.setRowSelected,
      onRemove: _controller.removeRow,
      onResolution: _controller.setDuplicateResolution,
      onFieldChoice: _controller.setDuplicateFieldChoice,
      onTargetSelected: _controller.setDuplicateUpdateTarget,
      onSubscriptionTargetSelected: _controller.setSubscriptionAccountTarget,
    ),
    DataImportWizardStep.confirmation => _ConfirmationStep(
      state: state,
      onConfirmed: _controller.setFinalConfirmation,
    ),
    DataImportWizardStep.result => _ResultStep(
      state: state,
      pendingDraftCount: widget.pendingDraftCount,
      onOpenPendingSubscriptions: widget.onOpenPendingSubscriptions,
      onDone: () => Navigator.of(context).pop(),
    ),
  };
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});

  final DataImportWizardStep step;

  @override
  Widget build(BuildContext context) {
    final index = step.index + 1;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('第 {current} 步，共 7 步', <String, Object?>{
                'current': index,
              }),
              translate: false,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: index / 7),
          ],
        ),
      ),
    );
  }
}

class _WriteDisabledNotice extends StatelessWidget {
  const _WriteDisabledNotice();

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    color: Theme.of(context).colorScheme.errorContainer,
    child: const ListTile(
      leading: Icon(Icons.lock_outline),
      title: Text('当前不能批量导入'),
      subtitle: Text('订阅只读视图、保险库已锁定或正在处理其他写入。请回到真实或诱饵保险库的完整解锁状态后重试。'),
    ),
  );
}

class _ParsingNotice extends StatelessWidget {
  const _ParsingNotice({required this.progress, required this.onCancel});

  final double? progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('正在本机后台解析文件…'),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
              ],
            ),
          ),
          TextButton(onPressed: onCancel, child: const Text('取消解析')),
        ],
      ),
    ),
  );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.error_outline),
      title: const Text('未继续执行'),
      subtitle: Text(context.tr(message), translate: false),
    ),
  );
}

class _SourceStep extends StatelessWidget {
  const _SourceStep({
    required this.sources,
    required this.selectedSourceId,
    required this.onSelected,
  });

  final List<DataImportSourceOption> sources;
  final String? selectedSourceId;
  final Future<void> Function(String sourceId)? onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('选择数据来源', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('只启用已经过格式验证的适配器；也可以选择通用表格并在下一步核对字段映射。'),
      const SizedBox(height: 12),
      RadioGroup<String>(
        groupValue: selectedSourceId,
        onChanged: (value) {
          if (value != null) onSelected?.call(value);
        },
        child: Column(
          children: [
            for (final source in sources)
              RadioListTile<String>(
                value: source.id,
                enabled: source.verified && onSelected != null,
                title: Text(context.tr(source.label), translate: false),
                subtitle: Text(
                  context.tr(source.description),
                  translate: false,
                ),
                secondary: source.verified
                    ? const Icon(Icons.verified_outlined)
                    : const Icon(Icons.block_outlined),
              ),
          ],
        ),
      ),
    ],
  );
}

class _FileStep extends StatelessWidget {
  const _FileStep({
    required this.state,
    required this.onPick,
    required this.onAppend,
  });

  final DataImportUiState state;
  final Future<void> Function() onPick;
  final Future<void> Function() onAppend;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('选择一个文件', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text(
        '支持单个 XLSX、DOCX、CSV、TSV 或 TXT 文件，最大 10 MiB。XLSX 读取首个工作表，DOCX 读取首个表格；文件只在本次内存流程中处理。',
      ),
      const SizedBox(height: 6),
      const Text('此入口不读取 .asmbackup 加密备份或 .ics 日历文件。'),
      const SizedBox(height: 18),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Icon(Icons.upload_file_outlined, size: 42),
              const SizedBox(height: 10),
              if (state.fileName case final name?) ...[
                Text(name, translate: false, textAlign: TextAlign.center),
                Text(
                  context.tr('{bytes} 字节', <String, Object?>{
                    'bytes': state.fileSize,
                  }),
                  translate: false,
                ),
                if (state.errorMessage == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '文件已读取；可追加配套表，或点击“下一步”核对字段。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (state.additionalFileName case final additionalName?) ...[
                  const SizedBox(height: 6),
                  Text(
                    context.tr('配套文件：{name} · {bytes} 字节', <String, Object?>{
                      'name': additionalName,
                      'bytes': state.additionalFileSize,
                    }),
                    translate: false,
                    textAlign: TextAlign.center,
                  ),
                ],
              ] else
                const Text('尚未选择文件'),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey<String>('data-import-file-picker'),
                onPressed: state.working ? null : onPick,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(state.fileName == null ? '选择文件' : '重新选择文件'),
              ),
              if (state.fileName != null && state.additionalFileName == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    key: const ValueKey<String>(
                      'data-import-append-file-picker',
                    ),
                    onPressed: state.working ? null : onAppend,
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('追加配套账号或订阅表'),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _MappingStep extends StatelessWidget {
  const _MappingStep({
    required this.state,
    required this.onChanged,
    required this.onAcceptSuggestion,
    required this.onAcceptAllSuggestions,
    required this.onIgnoreAllSuggestions,
  });

  final DataImportUiState state;
  final Future<void> Function({
    required int columnIndex,
    required String? targetField,
  })
  onChanged;
  final void Function(String suggestionId) onAcceptSuggestion;
  final VoidCallback onAcceptAllSuggestions;
  final VoidCallback onIgnoreAllSuggestions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('检测并核对字段映射', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text(
        context.tr('检测结果：{format}', <String, Object?>{
          'format': state.detectedFormat ?? '待检测',
        }),
        translate: false,
      ),
      const SizedBox(height: 12),
      for (final mapping in state.mappings)
        Card(
          child: ListTile(
            title: Text(mapping.sourceLabel, translate: false),
            subtitle: mapping.excludedAsSensitive
                ? const Text('该列属于排除的敏感字段，不会进入预览或保险库。')
                : null,
            trailing: SizedBox(
              width: 150,
              child: DropdownButtonFormField<String?>(
                key: ValueKey<String>(
                  'mapping-${mapping.columnIndex}-${mapping.targetField}',
                ),
                initialValue: mapping.targetField,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '导入为',
                  isDense: true,
                ),
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('忽略此列'),
                  ),
                  for (final target in mapping.availableTargets)
                    DropdownMenuItem<String?>(
                      value: target,
                      child: Text(
                        context.tr(_targetFieldLabel(target)),
                        translate: false,
                      ),
                    ),
                ],
                onChanged: mapping.excludedAsSensitive
                    ? null
                    : (value) => onChanged(
                        columnIndex: mapping.columnIndex,
                        targetField: value,
                      ),
              ),
            ),
          ),
        ),
      if (state.fieldSuggestions.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '登录账号字段建议',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text('只在目标邮箱或手机号为空时建议；接受后登录账号原值保持不变。'),
                for (final suggestion in state.fieldSuggestions)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${context.tr(suggestion.targetField == 'email' ? '邮箱' : '手机号')} · ${suggestion.value}',
                      translate: false,
                    ),
                    trailing: suggestion.accepted
                        ? const Icon(Icons.check_circle_outline)
                        : TextButton(
                            onPressed: () => onAcceptSuggestion(suggestion.id),
                            child: const Text('接受此项'),
                          ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: onIgnoreAllSuggestions,
                      child: const Text('全部忽略'),
                    ),
                    FilledButton.tonal(
                      onPressed: onAcceptAllSuggestions,
                      child: const Text('全部接受'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      if (state.warnings.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final warning in state.warnings)
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(context.tr(warning), translate: false),
          ),
      ],
    ],
  );
}

class _PasswordPreviewStep extends StatelessWidget {
  const _PasswordPreviewStep({
    required this.state,
    required this.onMaskedPasswordConfirmed,
    required this.onBrandSelected,
    required this.onBrandIgnored,
  });

  final DataImportUiState state;
  final void Function(String rowId, bool confirmed) onMaskedPasswordConfirmed;
  final void Function(String rowId, String brandId) onBrandSelected;
  final void Function(String rowId) onBrandIgnored;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('预览密码状态', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('这里只显示密码状态，不显示密码原文，也不提供“全部显示”。'),
      const SizedBox(height: 12),
      for (final row in state.rows)
        if (row.passwordStatus == DataImportPasswordStatus.maskedReviewRequired)
          CheckboxListTile(
            key: ValueKey<String>('masked-password-confirm-${row.id}'),
            value: row.maskedPasswordConfirmed,
            onChanged: (value) =>
                onMaskedPasswordConfirmed(row.id, value ?? false),
            secondary: const Icon(Icons.visibility_off_outlined),
            title: Text(_localizedRowTitle(context, row), translate: false),
            subtitle: const Text('疑似星号或圆点遮挡占位值；默认不导入。仅在确认这就是要保存的真实密码时勾选。'),
          )
        else
          ListTile(
            leading: Icon(
              row.passwordStatus == DataImportPasswordStatus.encryptedForImport
                  ? Icons.password_outlined
                  : Icons.no_encryption_outlined,
            ),
            title: Text(_localizedRowTitle(context, row), translate: false),
            subtitle: Text(row.subtitle, translate: false),
            trailing: Text(
              context.tr(_passwordStatusLabel(row.passwordStatus)),
              translate: false,
            ),
          ),
      for (final row in state.rows)
        if (row.brandSuggestionOptions.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_localizedRowTitle(context, row), translate: false),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: row.selectedBrandSuggestionId,
                    decoration: const InputDecoration(labelText: '品牌匹配候选'),
                    items: [
                      for (final option in row.brandSuggestionOptions.entries)
                        DropdownMenuItem(
                          value: option.key,
                          child: Text(option.value, translate: false),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) onBrandSelected(row.id, value);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => onBrandIgnored(row.id),
                      child: Text(
                        row.brandSuggestionsIgnored ? '已忽略品牌建议' : '忽略这些建议',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    ],
  );
}

String _passwordStatusLabel(DataImportPasswordStatus status) =>
    switch (status) {
      DataImportPasswordStatus.absent => '未包含密码',
      DataImportPasswordStatus.encryptedForImport => '将加密导入',
      DataImportPasswordStatus.excluded => '已按规则排除',
      DataImportPasswordStatus.maskedReviewRequired => '遮挡占位值 · 默认排除',
    };

String _localizedRowTitle(BuildContext context, DataImportPreviewRow row) {
  final key = row.titleTranslationKey;
  if (key == null) return row.title;
  return context.tr(key, row.titleTranslationValues);
}

String _localizedRowDetail(BuildContext context, DataImportPreviewRow row) {
  final issueKey = row.issueTranslationKey;
  if (issueKey != null) {
    return context.tr(issueKey, row.issueTranslationValues);
  }
  final duplicateKey = row.duplicateDescriptionTranslationKey;
  if (duplicateKey != null) {
    return context.tr(duplicateKey, row.duplicateDescriptionTranslationValues);
  }
  return row.issue ?? row.duplicateDescription ?? row.subtitle;
}

class _DuplicateStep extends StatelessWidget {
  const _DuplicateStep({
    required this.state,
    required this.onSelected,
    required this.onRemove,
    required this.onResolution,
    required this.onFieldChoice,
    required this.onTargetSelected,
    required this.onSubscriptionTargetSelected,
  });

  final DataImportUiState state;
  final void Function(String rowId, bool selected) onSelected;
  final void Function(String rowId) onRemove;
  final void Function(String rowId, DataImportDuplicateResolution resolution)
  onResolution;
  final void Function(String rowId, String fieldName, bool useImportedValue)
  onFieldChoice;
  final void Function(String rowId, String existingAccountId) onTargetSelected;
  final void Function(String rowId, String existingAccountId)
  onSubscriptionTargetSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('处理重复项', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('默认跳过疑似重复项。合并只补充空字段，不覆盖已有密码或非空内容。'),
      const SizedBox(height: 12),
      for (final row in state.rows)
        Card(
          child: Column(
            children: [
              CheckboxListTile(
                value: row.selected,
                onChanged: (value) => onSelected(row.id, value ?? false),
                title: Text(_localizedRowTitle(context, row), translate: false),
                subtitle: Text(
                  _localizedRowDetail(context, row),
                  translate: false,
                ),
                secondary: IconButton(
                  tooltip: context.tr('从本次导入中移除'),
                  onPressed: () => onRemove(row.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
              if (row.duplicateDescription != null && row.selected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: DropdownButtonFormField<DataImportDuplicateResolution>(
                    key: ValueKey<String>(
                      'duplicate-resolution-${row.id}-${row.duplicateResolution.name}',
                    ),
                    initialValue: row.duplicateResolution,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '重复项处理'),
                    items: const [
                      DropdownMenuItem(
                        value: DataImportDuplicateResolution.skip,
                        child: Text('跳过'),
                      ),
                      DropdownMenuItem(
                        value: DataImportDuplicateResolution.mergeMissingFields,
                        child: Text(
                          '只补充已有记录的空字段',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: DataImportDuplicateResolution.fieldByField,
                        child: Text('逐字段选择'),
                      ),
                      DropdownMenuItem(
                        value: DataImportDuplicateResolution.createAnother,
                        child: Text('仍创建另一条记录'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onResolution(row.id, value);
                    },
                  ),
                ),
              if (row.selected &&
                  (row.duplicateResolution ==
                          DataImportDuplicateResolution.mergeMissingFields ||
                      row.duplicateResolution ==
                          DataImportDuplicateResolution.fieldByField) &&
                  row.duplicateTargetOptions.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: row.selectedDuplicateTargetId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '选择要更新的已有账号'),
                    items: [
                      for (final option in row.duplicateTargetOptions.entries)
                        DropdownMenuItem(
                          value: option.key,
                          child: Text(
                            option.value,
                            translate: false,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) onTargetSelected(row.id, value);
                    },
                  ),
                ),
              if (row.selected &&
                  row.kind == DataImportRecordKind.subscription &&
                  row.subscriptionTargetRequired)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'subscription-target-${row.id}-${row.selectedSubscriptionTargetId}',
                    ),
                    initialValue: row.selectedSubscriptionTargetId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '关联到保险库中的账号',
                      helperText: '也可返回文件步骤追加含相同 account_key 的账号表。',
                    ),
                    items: [
                      for (final option
                          in row.subscriptionTargetOptions.entries)
                        DropdownMenuItem(
                          value: option.key,
                          child: Text(
                            option.value,
                            translate: false,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: row.subscriptionTargetOptions.isEmpty
                        ? null
                        : (value) {
                            if (value != null) {
                              onSubscriptionTargetSelected(row.id, value);
                            }
                          },
                  ),
                ),
              if (row.selected &&
                  row.duplicateResolution ==
                      DataImportDuplicateResolution.fieldByField)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('逐字段决定（已有密码原文不会显示）'),
                      const SizedBox(height: 6),
                      if (row.fieldComparisons.isEmpty)
                        const Text('请先选择要更新的已有账号，再逐字段核对。')
                      else
                        for (final comparison in row.fieldComparisons.values)
                          _FieldComparisonCard(
                            comparison: comparison,
                            isConflict: row.conflictingFields.contains(
                              comparison.fieldName,
                            ),
                            choice: row.fieldChoices[comparison.fieldName],
                            onChoice: (value) => onFieldChoice(
                              row.id,
                              comparison.fieldName,
                              value,
                            ),
                          ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

class _FieldComparisonCard extends StatelessWidget {
  const _FieldComparisonCard({
    required this.comparison,
    required this.isConflict,
    required this.choice,
    required this.onChoice,
  });

  final DataImportFieldComparison comparison;
  final bool isConflict;
  final bool? choice;
  final ValueChanged<bool> onChoice;

  @override
  Widget build(BuildContext context) {
    final passwordStatus = comparison.passwordComparison;
    return Card.outlined(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _conflictFieldLabel(comparison.fieldName),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (passwordStatus == null) ...[
              _ComparisonValue(
                label: 'Cardock 现有内容',
                value: comparison.existingValue,
              ),
              const SizedBox(height: 8),
              _ComparisonValue(
                label: '本次导入内容',
                value: comparison.importedValue,
              ),
            ] else
              Semantics(
                label: context.tr('密码比较结果'),
                value: context.tr(_passwordComparisonLabel(passwordStatus)),
                child: Text(_passwordComparisonLabel(passwordStatus)),
              ),
            const SizedBox(height: 10),
            Text('用户选择', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            if (isConflict) ...[
              if (passwordStatus == DataImportPasswordComparison.different &&
                  choice == null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('密码不同，必须逐条明确确认；不会批量覆盖。'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('保留已有'),
                    selected: choice == false,
                    onSelected: (_) => onChoice(false),
                  ),
                  ChoiceChip(
                    label: Text(
                      comparison.fieldName == 'notes' ? '使用导入（追加）' : '使用导入',
                    ),
                    selected: choice == true,
                    onSelected: (_) => onChoice(true),
                  ),
                ],
              ),
            ] else
              Text(_nonConflictDecisionLabel(comparison)),
          ],
        ),
      ),
    );
  }
}

class _ComparisonValue extends StatelessWidget {
  const _ComparisonValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? context.tr('未填写') : value,
          translate: false,
          softWrap: true,
        ),
      ],
    ),
  );
}

String _passwordComparisonLabel(DataImportPasswordComparison comparison) =>
    switch (comparison) {
      DataImportPasswordComparison.same => '相同',
      DataImportPasswordComparison.different => '不同',
      DataImportPasswordComparison.existingEmpty => '现有为空',
      DataImportPasswordComparison.importedEmpty ||
      DataImportPasswordComparison.bothEmpty => '导入为空',
    };

String _nonConflictDecisionLabel(DataImportFieldComparison comparison) {
  if (comparison.isPassword) return '保留已有';
  if (comparison.existingValue.isEmpty && comparison.importedValue.isNotEmpty) {
    return '使用导入';
  }
  return '保留已有';
}

String _conflictFieldLabel(String field) => switch (field) {
  'platformName' => '平台名称',
  'loginAccount' => '登录账号',
  'phone' => '手机号',
  'email' => '邮箱',
  'password' => '密码（仅状态比较）',
  'url' => '网址',
  'notes' => '备注（使用导入=追加）',
  _ => field,
};

class _ConfirmationStep extends StatelessWidget {
  const _ConfirmationStep({required this.state, required this.onConfirmed});

  final DataImportUiState state;
  final void Function(bool confirmed) onConfirmed;

  @override
  Widget build(BuildContext context) {
    final plan = state.planSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('最终确认', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline),
          title: Text('目标保险库：当前真实保险库'),
          subtitle: Text('提交前和提交时都会重新核对保险库范围与数据代次。'),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('新增账号'),
                trailing: Text('${plan?.newAccounts ?? 0}', translate: false),
              ),
              ListTile(
                title: const Text('更新账号'),
                trailing: Text(
                  '${plan?.updatedAccounts ?? 0}',
                  translate: false,
                ),
              ),
              ListTile(
                title: const Text('跳过账号'),
                trailing: Text(
                  '${plan?.skippedAccounts ?? 0}',
                  translate: false,
                ),
              ),
              ListTile(
                title: const Text('正式订阅'),
                trailing: Text(
                  '${plan?.formalSubscriptions ?? 0}',
                  translate: false,
                ),
              ),
              ListTile(
                title: const Text('待完善订阅'),
                trailing: Text(
                  '${plan?.pendingSubscriptionDrafts ?? 0}',
                  translate: false,
                ),
              ),
              ListTile(
                title: const Text('不支持项目'),
                trailing: Text(
                  '${plan?.unsupportedItems ?? 0}',
                  translate: false,
                ),
              ),
              ListTile(
                title: const Text('额度复核'),
                subtitle: Text(
                  context.tr(
                    '剩余账号 {accounts} · 剩余订阅 {subscriptions}',
                    <String, Object?>{
                      'accounts': plan?.remainingAccounts ?? context.tr('不限'),
                      'subscriptions':
                          plan?.remainingSubscriptions ?? context.tr('不限'),
                    },
                  ),
                  translate: false,
                ),
                trailing: Icon(
                  plan?.quotaAllowed == true
                      ? Icons.check_circle_outline
                      : Icons.block_outlined,
                ),
              ),
            ],
          ),
        ),
        CheckboxListTile(
          key: const ValueKey<String>('data-import-final-confirmation'),
          value: state.finalConfirmation,
          onChanged: (value) => onConfirmed(value ?? false),
          title: const Text('我已核对来源、映射、密码状态和重复项处理。'),
          subtitle: const Text('提交时会再次核对权威预览 token、保险库代次和免费版数量限制；任何冲突都会整批停止。'),
        ),
      ],
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({
    required this.state,
    required this.pendingDraftCount,
    required this.onOpenPendingSubscriptions,
    required this.onDone,
  });

  final DataImportUiState state;
  final int pendingDraftCount;
  final Future<void> Function()? onOpenPendingSubscriptions;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final summary = state.commitSummary;
    final effectivePendingDraftCount =
        pendingDraftCount + (summary?.pendingSubscriptionDrafts ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          summary == null ? Icons.error_outline : Icons.task_alt,
          size: 58,
          color: summary == null
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          summary == null ? '导入未完成' : '批量导入已完成',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        if (summary != null) ...[
          const SizedBox(height: 12),
          Text(
            context.tr(
              '账号 {accounts} · 正式订阅 {formal} · 待完善 {pending} · 合并 {merged} · 跳过 {skipped} · 不支持 {unsupported}',
              <String, Object?>{
                'accounts': summary.importedAccounts,
                'formal': summary.formalSubscriptions,
                'pending': summary.pendingSubscriptionDrafts,
                'merged': summary.mergedRecords,
                'skipped': summary.skippedRecords,
                'unsupported': summary.unsupportedRecords,
              },
            ),
            translate: false,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            summary.rollbackAvailable
                ? '最近一次批量导入的本机加密回滚可用。'
                : '本次没有生成可用的批量导入回滚；请先核对记录。',
            textAlign: TextAlign.center,
          ),
          Text(
            context.tr(
              '保留密码 {preserved} · 掩码已排除 {masked} · 空密码 {empty} · 未映射列 {unmapped} · 未解决重复 {unresolved}',
              {
                'preserved': summary.preservedPasswords,
                'masked': summary.maskedPasswords,
                'empty': summary.emptyPasswords,
                'unmapped': summary.unmappedColumns,
                'unresolved': summary.unresolvedDuplicates,
              },
            ),
            translate: false,
          ),
          if (summary.warning case final warning?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr(warning),
                translate: false,
                textAlign: TextAlign.center,
              ),
            ),
        ],
        const SizedBox(height: 16),
        const Text(
          '源文件可能仍含明文密码。请先核对导入记录和加密备份，再自行处理源文件；Cardock 不会删除外部文件，也无法清理聊天、网盘、回收站或其他设备中的副本。自动备份只保护已导入的加密记录。',
          textAlign: TextAlign.center,
        ),
        if (effectivePendingDraftCount > 0 &&
            onOpenPendingSubscriptions != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onOpenPendingSubscriptions,
            icon: const Icon(Icons.edit_calendar_outlined),
            label: Text(
              context.tr('继续完善订阅（{count}）', <String, Object?>{
                'count': effectivePendingDraftCount,
              }),
              translate: false,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: onDone, child: const Text('完成并清空内存')),
      ],
    );
  }
}

String _targetFieldLabel(String field) => switch (field) {
  'accountKey' => '账号关联键',
  'platformName' => '平台名称',
  'loginAccount' => '登录账号',
  'phone' => '手机号',
  'email' => '邮箱',
  'password' => '密码',
  'url' => '网址',
  'notes' => '备注',
  'planName' => '方案名称',
  'amount' => '金额',
  'currency' => '币种',
  'billingCycle' => '账单周期',
  'subscriptionStartDate' => '首次订阅日期',
  'nextRenewalDate' => '下次续费日期',
  'autoRenew' => '自动续费',
  'paymentMethod' => '支付方式',
  'reminderDays' => '提前提醒天数',
  _ => field,
};

class _WizardActions extends StatelessWidget {
  const _WizardActions({
    required this.state,
    required this.onBack,
    required this.onNext,
  });

  final DataImportUiState state;
  final VoidCallback? onBack;
  final Future<void> Function()? onNext;

  @override
  Widget build(BuildContext context) {
    final isFirst = state.step == DataImportWizardStep.source;
    final isConfirmation = state.step == DataImportWizardStep.confirmation;
    final enabled =
        onNext != null &&
        (!isConfirmation || state.finalConfirmation) &&
        !state.hasBlockingIssues;
    return Material(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(16) > 24;
            final label = isConfirmation
                ? '确认并加密导入'
                : state.step == DataImportWizardStep.file
                ? '下一步：核对字段'
                : '下一步';
            final nextButton = compact
                ? FilledButton(
                    key: const ValueKey<String>('data-import-next'),
                    onPressed: enabled ? () => onNext!() : null,
                    child: state.working
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(label, textAlign: TextAlign.center),
                  )
                : FilledButton.icon(
                    key: const ValueKey<String>('data-import-next'),
                    onPressed: enabled ? () => onNext!() : null,
                    icon: state.working
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isConfirmation
                                ? Icons.lock_outline
                                : Icons.navigate_next,
                          ),
                    label: Text(label),
                  );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nextButton,
                  if (!isFirst) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: onBack,
                      child: const Text('上一步', textAlign: TextAlign.center),
                    ),
                  ],
                ],
              );
            }
            return Row(
              children: [
                if (!isFirst)
                  OutlinedButton(onPressed: onBack, child: const Text('上一步')),
                const Spacer(),
                nextButton,
              ],
            );
          },
        ),
      ),
    );
  }
}
