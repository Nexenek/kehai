import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/couple_info.dart';
import 'auth_repository.dart';

/// Wraps the custom /api/couple/create and /api/couple/join routes, plus
/// looking up the partner's `users` record once a couple exists.
class CoupleRepository {
  CoupleRepository(this._pb, this._authRepository);

  final PocketBase _pb;
  final AuthRepository _authRepository;

  Future<CoupleInfo> createCouple(String name) async {
    final json = await _pb.send<Map<String, dynamic>>(
      '/api/couple/create',
      method: 'POST',
      body: {'name': name},
    );
    await _authRepository.refresh();
    return CoupleInfo.fromJson(json);
  }

  Future<void> joinCouple(String code) async {
    await _pb.send<Map<String, dynamic>>(
      '/api/couple/join',
      method: 'POST',
      body: {'code': code},
    );
    await _authRepository.refresh();
  }

  /// The partner's `users` record — null if no partner has joined yet.
  Future<Partner?> fetchPartner() async {
    final coupleId = _authRepository.coupleId;
    final myId = _authRepository.currentUserId;
    if (coupleId == null) return null;

    try {
      final record = await _pb.collection('users').getFirstListItem(
            'couple = "$coupleId" && id != "$myId"',
          );
      return Partner(id: record.id, name: record.get<String>('name'));
    } on ClientException catch (e) {
      // 404 just means the partner hasn't joined yet.
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// The couple's `anniversary` date, for the "together N days" counter —
  /// null if it hasn't been set yet.
  Future<DateTime?> fetchAnniversary() async {
    final coupleId = _authRepository.coupleId;
    if (coupleId == null) return null;
    final record = await _pb.collection('couples').getOne(coupleId);
    return _parseAnniversary(record);
  }

  /// Either partner may set/update this — see couples.UpdateRule in
  /// server/migrations/3_shared_content.go.
  Future<void> updateAnniversary(DateTime date) async {
    final coupleId = _authRepository.coupleId;
    if (coupleId == null) return;
    await _pb.collection('couples').update(coupleId, body: {
      'anniversary': date.toUtc().toIso8601String(),
    });
  }

  /// Live updates to the couple record (currently just [anniversary]) so
  /// either partner setting/changing the day updates both screens without a
  /// refresh.
  Future<UnsubscribeFunc> subscribeAnniversary(void Function(DateTime? anniversary) onChange) {
    final coupleId = _authRepository.coupleId ?? '*';
    return _pb.collection('couples').subscribe(coupleId, (e) {
      if (e.record != null) onChange(_parseAnniversary(e.record!));
    });
  }

  DateTime? _parseAnniversary(RecordModel record) {
    final raw = record.get<String>('anniversary');
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }
}
