import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/auth_repository.dart';
import '../../../core/strings/app_strings.dart';

/// Drives the login/register onboarding step. Toggles between the two
/// modes and reports friendly errors from PocketBase's [ClientException].
class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._authRepository);

  final AuthRepository _authRepository;

  bool isRegisterMode = false;
  bool isSubmitting = false;
  String? errorMessage;

  void toggleMode() {
    isRegisterMode = !isRegisterMode;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> submit({required String email, required String password, String name = ''}) async {
    if (email.trim().isEmpty || password.isEmpty) {
      errorMessage = AppStrings.authFailed;
      notifyListeners();
      return false;
    }
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (isRegisterMode) {
        await _authRepository.register(
          email: email.trim(),
          password: password,
          name: name.trim().isEmpty ? email.trim() : name.trim(),
        );
      } else {
        await _authRepository.login(email: email.trim(), password: password);
      }
      isSubmitting = false;
      notifyListeners();
      return true;
    } on ClientException catch (e) {
      isSubmitting = false;
      errorMessage = _friendlyMessage(e);
      notifyListeners();
      return false;
    } catch (_) {
      isSubmitting = false;
      errorMessage = AppStrings.authFailed;
      notifyListeners();
      return false;
    }
  }

  String _friendlyMessage(ClientException e) {
    final serverMessage = e.response['message'] as String?;
    if (serverMessage != null && serverMessage.isNotEmpty) {
      return '$serverMessage (・_・;)';
    }
    return AppStrings.authFailed;
  }
}
