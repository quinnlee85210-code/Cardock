import 'package:flutter/material.dart';

/// In-memory page locations only. Never retains widgets, builders, form values,
/// or decrypted records across a lock. Each unlock creates fresh pages.
class VaultNavigation extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];
  final handlers = <String, void Function(RouteSettings)>{};
  List<RouteSettings> _savedPages = [];
  String? _savedScope;
  int selectedIndex = 0;
  int _savedIndex = 0;
  int _epoch = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) return;
    final index = _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
  }

  void lock(String? scope) {
    _epoch++;
    _savedScope = scope;
    _savedIndex = selectedIndex;
    _savedPages = [];
    if (scope != null) {
      for (final route in _routes.skip(1)) {
        if (route is! PageRoute) continue; // Never resume confirmations.
        if (route.settings is! VaultPageLocation) break;
        _savedPages.add(route.settings);
      }
    }
    handlers.clear();
  }

  int beginSession(String? scope, int defaultIndex) {
    if (scope == null || scope != _savedScope) {
      _savedPages = [];
      _savedScope = null;
      return selectedIndex = defaultIndex;
    }
    return selectedIndex = _savedIndex;
  }

  Future<void> restore(String? scope) async {
    final epoch = _epoch;
    final pages = _savedPages;
    _savedPages = [];
    if (scope == null || scope != _savedScope) return;
    _savedScope = null;
    for (final page in pages) {
      if (epoch != _epoch) return;
      final open = handlers[page.name];
      if (open == null) break;
      open(page);
      await WidgetsBinding.instance.endOfFrame;
    }
  }
}

class VaultPageLocation extends RouteSettings {
  const VaultPageLocation(String name, {this.recordId, this.tab = 0})
    : super(name: name);
  final String? recordId;
  final int tab;
}

class VaultNavigationScope extends InheritedWidget {
  const VaultNavigationScope({
    required this.navigation,
    required super.child,
    super.key,
  });
  final VaultNavigation navigation;
  static VaultNavigation? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<VaultNavigationScope>()
      ?.navigation;
  @override
  bool updateShouldNotify(VaultNavigationScope oldWidget) =>
      navigation != oldWidget.navigation;
}
