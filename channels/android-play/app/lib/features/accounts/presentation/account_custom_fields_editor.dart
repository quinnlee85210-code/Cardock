import 'dart:async';

import '../../../l10n/context_l10n.dart';
import '../../../l10n/localized_material.dart';
import '../../../shared/widgets/cardock_ui.dart';
import '../domain/account_custom_field.dart';

String customFieldTypeLabel(AccountCustomFieldType type) => switch (type) {
  AccountCustomFieldType.text => '普通文本',
  AccountCustomFieldType.sensitiveText => '敏感文本',
  AccountCustomFieldType.url => 'URL',
  AccountCustomFieldType.date => '日期',
  AccountCustomFieldType.number => '数字',
};

class CustomFieldEditorRow {
  CustomFieldEditorRow({
    required this.id,
    required this.type,
    String name = '',
    String value = '',
    this.revision = 0,
  }) : name = TextEditingController(text: name),
       value = TextEditingController(text: value);
  final String id;
  AccountCustomFieldType type;
  final int revision;
  final TextEditingController name;
  final TextEditingController value;
  void dispose() {
    name.clear();
    value.clear();
    name.dispose();
    value.dispose();
  }
}

class AccountCustomFieldsController extends ChangeNotifier {
  AccountCustomFieldsController([List<AccountCustomField> fields = const []]) {
    for (final field in fields) {
      _attach(
        CustomFieldEditorRow(
          id: field.id,
          type: field.type,
          name: field.name,
          value: field.value,
          revision: field.revision,
        ),
      );
    }
  }
  final List<CustomFieldEditorRow> rows = [];
  int _counter = 0;
  VoidCallback? onDraftChanged;
  void _changed() {
    notifyListeners();
    onDraftChanged?.call();
  }

  void _attach(CustomFieldEditorRow row) {
    rows.add(row);
    row.name.addListener(_changed);
    row.value.addListener(_changed);
  }

  void add() {
    if (rows.length >= 10) throw ArgumentError('每个账号最多 10 个自定义字段');
    _attach(
      CustomFieldEditorRow(
        id: 'field-${DateTime.now().microsecondsSinceEpoch}-${_counter++}',
        type: AccountCustomFieldType.text,
      ),
    );
    _changed();
  }

  void remove(CustomFieldEditorRow row) {
    rows.remove(row);
    row.name.removeListener(_changed);
    row.value.removeListener(_changed);
    row.dispose();
    _changed();
  }

  void move(int from, int to) {
    if (to < 0 || to >= rows.length) return;
    final row = rows.removeAt(from);
    rows.insert(to, row);
    _changed();
  }

  void setType(CustomFieldEditorRow row, AccountCustomFieldType type) {
    row.type = type;
    _changed();
  }

  List<Map<String, Object?>> exportEditorFields() => [
    for (var index = 0; index < rows.length; index++)
      {
        'id': rows[index].id,
        'name': rows[index].name.text,
        'type': rows[index].type.code,
        'value': rows[index].value.text,
        'order': index,
        'revision': rows[index].revision,
      },
  ];
  void restoreEditorFields(Object? raw) {
    if (raw == null) return;
    if (raw is! List || raw.length > 10) {
      throw const FormatException('自定义字段草稿无效');
    }
    final restored = <CustomFieldEditorRow>[];
    for (final entry in raw) {
      if (entry is! Map ||
          entry['id'] is! String ||
          entry['name'] is! String ||
          entry['value'] is! String) {
        throw const FormatException('自定义字段草稿无效');
      }
      final type = AccountCustomFieldType.values
          .where((t) => t.code == entry['type'])
          .firstOrNull;
      if (type == null) throw const FormatException('不支持的自定义字段类型');
      restored.add(
        CustomFieldEditorRow(
          id: entry['id'] as String,
          type: type,
          name: entry['name'] as String,
          value: entry['value'] as String,
          revision: entry['revision'] is int ? entry['revision'] as int : 0,
        ),
      );
    }
    for (final row in rows) {
      row.name.removeListener(_changed);
      row.value.removeListener(_changed);
      row.dispose();
    }
    rows.clear();
    for (final row in restored) {
      _attach(row);
    }
    _changed();
  }

  List<AccountCustomField> toFields() => validateAccountCustomFields([
    for (var index = 0; index < rows.length; index++)
      AccountCustomField(
        id: rows[index].id,
        name: rows[index].name.text,
        type: rows[index].type,
        value: rows[index].value.text,
        order: index,
        revision: rows[index].revision,
      ),
  ]);
  @override
  void dispose() {
    onDraftChanged = null;
    for (final row in rows) {
      row.name.removeListener(_changed);
      row.value.removeListener(_changed);
      row.dispose();
    }
    rows.clear();
    super.dispose();
  }
}

class AccountCustomFieldsEditor extends StatefulWidget {
  const AccountCustomFieldsEditor({
    required this.controller,
    this.revealDuration = const Duration(seconds: 30),
    super.key,
  });
  final AccountCustomFieldsController controller;
  final Duration revealDuration;
  @override
  State<AccountCustomFieldsEditor> createState() =>
      _AccountCustomFieldsEditorState();
}

class _AccountCustomFieldsEditorState extends State<AccountCustomFieldsEditor>
    with WidgetsBindingObserver {
  final Set<String> _visible = {};
  final Map<String, Timer> _timers = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _hideAll();
  }

  void _hideAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (mounted) setState(_visible.clear);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _visible.clear();
    _timers.clear();
    super.dispose();
  }

  void _toggle(String id) {
    _timers.remove(id)?.cancel();
    setState(() {
      if (!_visible.add(id)) _visible.remove(id);
    });
    if (_visible.contains(id)) {
      _timers[id] = Timer(widget.revealDuration, () {
        if (mounted) setState(() => _visible.remove(id));
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => CardockSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('自定义字段', style: Theme.of(context).textTheme.titleMedium),
          Text(
            context.tr('已使用 {count}/10 个字段；空值也占一个名额。', {
              'count': widget.controller.rows.length,
            }),
            translate: false,
          ),
          for (var index = 0; index < widget.controller.rows.length; index++)
            _buildRow(context, widget.controller.rows[index], index),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('add-account-custom-field'),
            onPressed: () {
              if (widget.controller.rows.length >= 10) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('每个账号最多 10 个自定义字段')),
                );
                return;
              }
              widget.controller.add();
            },
            icon: const Icon(Icons.add),
            label: const Text('添加自定义字段'),
          ),
        ],
      ),
    ),
  );
  Widget _buildRow(BuildContext context, CustomFieldEditorRow row, int index) =>
      Padding(
        key: ValueKey('custom-field-editor-${row.id}'),
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: context.tr('自定义字段 {index}', {'index': index + 1}),
              child: Text(
                context.tr('字段 {index}', {'index': index + 1}),
                translate: false,
              ),
            ),
            TextFormField(
              key: ValueKey('custom-field-name-$index'),
              controller: row.name,
              maxLength: 100,
              decoration: InputDecoration(labelText: context.tr('字段名称 *')),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? context.tr('请输入字段名称') : null,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AccountCustomFieldType>(
              key: ValueKey('custom-field-type-$index-${row.type.name}'),
              initialValue: row.type,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('字段类型')),
              items: [
                for (final type in AccountCustomFieldType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(customFieldTypeLabel(type)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  _timers.remove(row.id)?.cancel();
                  _visible.remove(row.id);
                  widget.controller.setType(row, value);
                }
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('custom-field-value-$index'),
              controller: row.value,
              maxLength: 10000,
              obscureText:
                  row.type == AccountCustomFieldType.sensitiveText &&
                  !_visible.contains(row.id),
              maxLines: row.type == AccountCustomFieldType.text ? 3 : 1,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: row.type == AccountCustomFieldType.number
                  ? const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    )
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: context.tr('字段值（可留空）'),
                counterText: '',
                helperText: row.type == AccountCustomFieldType.date
                    ? context.tr('日期格式：YYYY-MM-DD')
                    : row.type == AccountCustomFieldType.number
                    ? context.tr('精确十进制，例如 123.4500；不使用科学计数。')
                    : null,
                suffixIcon: row.type == AccountCustomFieldType.sensitiveText
                    ? IconButton(
                        key: ValueKey('reveal-custom-field-editor-$index'),
                        tooltip: context.tr(
                          _visible.contains(row.id) ? '隐藏敏感值' : '临时显示敏感值30秒',
                        ),
                        onPressed: () => _toggle(row.id),
                        icon: Icon(
                          _visible.contains(row.id)
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      )
                    : null,
              ),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                IconButton(
                  key: ValueKey('move-custom-field-up-$index'),
                  tooltip: context.tr('上移字段'),
                  onPressed: index == 0
                      ? null
                      : () => widget.controller.move(index, index - 1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  key: ValueKey('move-custom-field-down-$index'),
                  tooltip: context.tr('下移字段'),
                  onPressed: index == widget.controller.rows.length - 1
                      ? null
                      : () => widget.controller.move(index, index + 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  key: ValueKey('remove-custom-field-$index'),
                  tooltip: context.tr('删除字段'),
                  onPressed: () {
                    _timers.remove(row.id)?.cancel();
                    _visible.remove(row.id);
                    widget.controller.remove(row);
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      );
}
