enum RecordDisplayMode { expandedCards, collapsibleCards, compactList }

extension RecordDisplayModePresentation on RecordDisplayMode {
  String get storageValue => name;

  String get label => switch (this) {
    RecordDisplayMode.expandedCards => '展开卡片',
    RecordDisplayMode.collapsibleCards => '可折叠卡片',
    RecordDisplayMode.compactList => '紧凑列表',
  };
}

RecordDisplayMode? recordDisplayModeFromStorage(Object? value) {
  if (value is! String) {
    return null;
  }
  for (final mode in RecordDisplayMode.values) {
    if (mode.storageValue == value) {
      return mode;
    }
  }
  return null;
}
