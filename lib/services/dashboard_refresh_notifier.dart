import 'package:flutter/foundation.dart';

class DashboardRefreshNotifier extends ChangeNotifier {
  DashboardRefreshNotifier._();

  static final DashboardRefreshNotifier instance = DashboardRefreshNotifier._();

  void notifyCheckInRegistered() => notifyListeners();
}
