import 'package:flutter/foundation.dart';

import '../../../../app_controller.dart';
import '../../../core/strings/app_strings.dart';

enum _TestState { idle, testing, ok, failed }

/// Drives the "find your server" onboarding step: lets the user try a
/// connection before committing to it, then hands off to [AppController]
/// to persist it and move the app to the next stage.
class ServerSetupViewModel extends ChangeNotifier {
  ServerSetupViewModel(this._controller);

  final AppController _controller;

  _TestState _testState = _TestState.idle;
  bool _submitting = false;
  String? _errorMessage;

  bool get isTesting => _testState == _TestState.testing;
  bool get testSucceeded => _testState == _TestState.ok;
  bool get testFailed => _testState == _TestState.failed;
  bool get isSubmitting => _submitting;
  String? get errorMessage => _errorMessage;

  Future<void> testConnection(String url) async {
    if (url.trim().isEmpty) {
      _errorMessage = AppStrings.connectionFailed;
      _testState = _TestState.failed;
      notifyListeners();
      return;
    }
    _testState = _TestState.testing;
    _errorMessage = null;
    notifyListeners();

    final ok = await _controller.testConnection(url.trim());
    _testState = ok ? _TestState.ok : _TestState.failed;
    _errorMessage = ok ? null : AppStrings.connectionFailed;
    notifyListeners();
  }

  Future<bool> confirmAndContinue(String url) async {
    if (url.trim().isEmpty) return false;
    _submitting = true;
    _errorMessage = null;
    notifyListeners();

    final ok = await _controller.confirmServer(url.trim());
    _submitting = false;
    if (!ok) _errorMessage = _controller.connectionError ?? AppStrings.connectionFailed;
    notifyListeners();
    return ok;
  }
}
