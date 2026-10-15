import '../../l10n/context_l10n.dart';
import '../../l10n/localized_material.dart';

enum AppDestination {
  home('首页', Icons.home_outlined, Icons.home_rounded),
  accounts('账号', Icons.badge_outlined, Icons.badge_rounded),
  subscriptions('订阅', Icons.event_repeat_outlined, Icons.event_repeat_rounded),
  settings('设置', Icons.settings_outlined, Icons.settings_rounded);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  NavigationDestination toNavigationDestination([BuildContext? context]) {
    return NavigationDestination(
      key: ValueKey<String>('nav-$name'),
      icon: Icon(icon),
      selectedIcon: Icon(selectedIcon),
      label: context == null ? label : context.tr(label),
    );
  }
}
