enum RecordSortMode {
  renewalSoonest,
  newestAdded,
  oldestAdded,
  nameAscending,
  accountCategory,
}

extension RecordSortModePresentation on RecordSortMode {
  String get storageValue => name;

  String get label => switch (this) {
    RecordSortMode.renewalSoonest => '待处理续费优先',
    RecordSortMode.newestAdded => '最近添加',
    RecordSortMode.oldestAdded => '最早添加',
    RecordSortMode.nameAscending => '名称顺序',
    RecordSortMode.accountCategory => '按账号分类',
  };
}

RecordSortMode? recordSortModeFromStorage(Object? value) {
  if (value is! String) {
    return null;
  }
  for (final mode in RecordSortMode.values) {
    if (mode.storageValue == value) {
      return mode;
    }
  }
  return null;
}
