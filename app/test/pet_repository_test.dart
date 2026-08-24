import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/repositories/pet_repository.dart';
import 'package:couples_app/domain/models/pet.dart';
import 'package:couples_app/ui/core/strings/app_strings.dart';

RecordModel _record(Map<String, dynamic> overrides) => RecordModel({
  'id': 'pet1',
  'collectionId': 'pets_col',
  'collectionName': 'pets',
  'couple': 'couple1',
  'name': 'mochi',
  'variant': 'cat',
  'outfit': 'bow',
  'fed_at': '2026-08-23 12:00:00.000Z',
  'pet_at': '2026-08-23 06:00:00.000Z',
  ...overrides,
});

void main() {
  group('petFromRecord', () {
    test('maps every field, dates coming back local', () {
      final pet = petFromRecord(_record({}));

      expect(pet.id, 'pet1');
      expect(pet.coupleId, 'couple1');
      expect(pet.name, 'mochi');
      expect(pet.displayName, 'mochi');
      expect(pet.variant, PetVariant.cat);
      expect(pet.outfit, PetOutfit.bow);
      expect(pet.fedAt?.toUtc(), DateTime.utc(2026, 8, 23, 12));
      expect(pet.petAt?.toUtc(), DateTime.utc(2026, 8, 23, 6));
      expect(pet.fedAt?.isUtc, isFalse);
    });

    test('an empty date is null ("never"), not epoch or now', () {
      final pet = petFromRecord(_record({'fed_at': '', 'pet_at': ''}));
      expect(pet.fedAt, isNull);
      expect(pet.petAt, isNull);
    });

    test('an unknown select value falls back to the default', () {
      final pet = petFromRecord(
        _record({'variant': 'dragon', 'outfit': 'jetpack'}),
      );
      expect(pet.variant, PetVariant.blob);
      expect(pet.outfit, PetOutfit.none);
    });

    test('a blank name shows as kehai-chan without being stored', () {
      final pet = petFromRecord(_record({'name': '   '}));
      expect(pet.name, '   ');
      expect(pet.displayName, AppStrings.petDefaultName);
    });
  });

  group('Pet.copyWith', () {
    test('changes one field and leaves the rest (and id) alone', () {
      final pet = petFromRecord(_record({}));
      final fed = pet.copyWith(fedAt: DateTime.utc(2027));

      expect(fed.id, pet.id);
      expect(fed.coupleId, pet.coupleId);
      expect(fed.name, pet.name);
      expect(fed.variant, pet.variant);
      expect(fed.outfit, pet.outfit);
      expect(fed.petAt, pet.petAt);
      expect(fed.fedAt, DateTime.utc(2027));
    });
  });

  group('petEventFromRecord', () {
    RecordModel eventRecord(Map<String, dynamic> overrides) => RecordModel({
      'id': 'ev1',
      'collectionId': 'pet_events_col',
      'collectionName': 'pet_events',
      'couple': 'couple1',
      'user': 'userA',
      'type': 'feed',
      'created': '2026-08-23 12:00:00.000Z',
      ...overrides,
    });

    test('maps every field, created coming back local', () {
      final event = petEventFromRecord(eventRecord({}));

      expect(event.id, 'ev1');
      expect(event.coupleId, 'couple1');
      expect(event.userId, 'userA');
      expect(event.type, 'feed');
      expect(event.created.toUtc(), DateTime.utc(2026, 8, 23, 12));
      expect(event.created.isUtc, isFalse);
    });

    test('carries an unrecognised type through as-is (UI decides the fallback)', () {
      final event = petEventFromRecord(eventRecord({'type': 'mystery'}));
      expect(event.type, 'mystery');
    });
  });

  group('enums', () {
    test('every variant and outfit has a label', () {
      for (final variant in PetVariant.values) {
        expect(variant.label, isNotEmpty);
      }
      for (final outfit in PetOutfit.values) {
        expect(outfit.label, isNotEmpty);
      }
    });

    test('names match the server select values exactly', () {
      expect(PetVariant.values.map((v) => v.name), ['blob', 'cat', 'star']);
      expect(PetOutfit.values.map((o) => o.name), [
        'none',
        'bow',
        'scarf',
        'crown',
      ]);
    });
  });
}
