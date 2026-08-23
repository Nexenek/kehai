import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../../data/repositories/couple_repository.dart';
import '../../../../data/services/prefs_service.dart';
import '../../../../domain/models/couple_info.dart';
import '../../../core/strings/app_strings.dart';

enum CoupleSetupMode { choose, create, join }

/// Drives "start our couple": create a new couple (and show its invite
/// code) or join an existing one with a partner's code.
class CoupleSetupViewModel extends ChangeNotifier {
  CoupleSetupViewModel(this._coupleRepository, this._prefs);

  final CoupleRepository _coupleRepository;
  final PrefsService _prefs;

  CoupleSetupMode mode = CoupleSetupMode.choose;
  bool isSubmitting = false;
  String? errorMessage;
  CoupleInfo? createdCouple;

  void showCreate() {
    mode = CoupleSetupMode.create;
    errorMessage = null;
    notifyListeners();
  }

  void showJoin() {
    mode = CoupleSetupMode.join;
    errorMessage = null;
    notifyListeners();
  }

  void back() {
    mode = CoupleSetupMode.choose;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> create(String name) async {
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      createdCouple = await _coupleRepository.createCouple(name.trim());
      if (createdCouple!.inviteCode.isNotEmpty) {
        await _prefs.setInviteCode(createdCouple!.inviteCode);
      }
      isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      isSubmitting = false;
      errorMessage = _friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> join(String code) async {
    if (code.trim().isEmpty) {
      errorMessage = AppStrings.coupleFailed;
      notifyListeners();
      return false;
    }
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _coupleRepository.joinCouple(code.trim());
      isSubmitting = false;
      notifyListeners();
      return true;
    } catch (e) {
      isSubmitting = false;
      errorMessage = _friendlyMessage(e);
      notifyListeners();
      return false;
    }
  }

  String _friendlyMessage(Object e) {
    if (e is ClientException) {
      final serverMessage = e.response['message'] as String?;
      if (serverMessage != null && serverMessage.isNotEmpty) return '$serverMessage (・_・;)';
    }
    return AppStrings.coupleFailed;
  }
}
