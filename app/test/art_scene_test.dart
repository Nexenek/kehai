import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/domain/art_scene.dart';
import 'package:couples_app/domain/models/ambient_line.dart';

ArtLayer _layer(
  String id, {
  ArtSlot slot = ArtSlot.base,
  Set<String> moods = const {},
  Set<String> ambient = const {},
  bool isDefault = false,
  double sort = 0,
}) => ArtLayer(
  id: id,
  coupleId: 'couple1',
  slot: slot,
  name: id,
  imageUrl: 'https://example.invalid/$id.png',
  sort: sort,
  conditions: ArtConditions(
    moods: moods,
    ambient: ambient,
    isDefault: isDefault,
  ),
);

void main() {
  group('specificity ladder', () {
    test('mood+ambient beats mood, which beats ambient, which beats '
        'default, which beats an unconditional layer', () {
      final both = _layer('both', moods: {'sleepy'}, ambient: {'music'});
      final moodOnly = _layer('mood', moods: {'sleepy'});
      final ambientOnly = _layer('ambient', ambient: {'music'});
      final fallback = _layer('default', isDefault: true);
      final wildcard = _layer('wildcard');

      final all = [wildcard, fallback, ambientOnly, moodOnly, both];

      ArtLayer? pick(List<ArtLayer> layers) => pickArtLayerForSlot(
        layers,
        ArtSlot.base,
        moodId: 'sleepy',
        ambientKind: 'music',
      );

      expect(pick(all)?.id, 'both');
      expect(pick(all..remove(both))?.id, 'mood');
      expect(pick(all..remove(moodOnly))?.id, 'ambient');
      expect(pick(all..remove(ambientOnly))?.id, 'default');
      expect(pick(all..remove(fallback))?.id, 'wildcard');
      expect(pick([]), isNull);
    });

    test('scores are exactly the documented rungs', () {
      expect(
        artLayerMatchScore(
          _layer('a', moods: {'cozy'}, ambient: {'away'}),
          moodId: 'cozy',
          ambientKind: 'away',
        ),
        artMatchMoodAndAmbient,
      );
      expect(
        artLayerMatchScore(
          _layer('a', moods: {'cozy'}),
          moodId: 'cozy',
          ambientKind: 'away',
        ),
        artMatchMood,
      );
      expect(
        artLayerMatchScore(
          _layer('a', ambient: {'away'}),
          moodId: 'cozy',
          ambientKind: 'away',
        ),
        artMatchAmbient,
      );
      expect(
        artLayerMatchScore(_layer('a', isDefault: true), moodId: 'cozy'),
        artMatchDefault,
      );
      expect(artLayerMatchScore(_layer('a'), moodId: 'cozy'), artMatchNone);
    });

    test('a layer whose mood does not match is ruled out — even if it is '
        'flagged as the slot default', () {
      final wrongMood = _layer(
        'sleepy-only',
        moods: {'sleepy'},
        isDefault: true,
      );
      expect(artLayerMatchScore(wrongMood, moodId: 'happy'), isNull);
      expect(
        pickArtLayerForSlot([wrongMood], ArtSlot.base, moodId: 'happy'),
        isNull,
      );
    });

    test('a layer whose ambient does not match is ruled out', () {
      final musicOnly = _layer('music-only', ambient: {'music'});
      expect(
        artLayerMatchScore(musicOnly, moodId: 'happy', ambientKind: 'away'),
        isNull,
      );
    });

    test('an unknown current state simply rules out layers that demand '
        'that dimension, rather than matching them', () {
      final needsMood = _layer('needs-mood', moods: {'happy'});
      final needsAmbient = _layer('needs-ambient', ambient: {'music'});
      expect(artLayerMatchScore(needsMood), isNull);
      expect(artLayerMatchScore(needsAmbient, moodId: 'happy'), isNull);
      // ...while an unconditional layer is unaffected by not knowing.
      expect(artLayerMatchScore(_layer('any')), artMatchNone);
    });

    test('a multi-value condition matches any member of the set', () {
      final cosy = _layer('cosy-set', moods: {'sleepy', 'cozy', 'meh'});
      for (final mood in ['sleepy', 'cozy', 'meh']) {
        expect(artLayerMatchScore(cosy, moodId: mood), artMatchMood);
      }
      expect(artLayerMatchScore(cosy, moodId: 'excited'), isNull);
    });
  });

  group('tie-breaking', () {
    test('equal specificity is broken by sort ascending', () {
      final low = _layer('bbb', moods: {'happy'}, sort: 1);
      final high = _layer('aaa', moods: {'happy'}, sort: 5);
      expect(
        pickArtLayerForSlot([high, low], ArtSlot.base, moodId: 'happy')?.id,
        'bbb',
      );
    });

    test('equal sort is broken by id, so the same state always composites '
        'the same scene', () {
      final a = _layer('aaa', moods: {'happy'});
      final b = _layer('bbb', moods: {'happy'});
      expect(
        pickArtLayerForSlot([b, a], ArtSlot.base, moodId: 'happy')?.id,
        'aaa',
      );
      expect(
        pickArtLayerForSlot([a, b], ArtSlot.base, moodId: 'happy')?.id,
        'aaa',
      );
    });
  });

  group('resolveArtScene', () {
    test('returns one layer per slot, in paint order', () {
      final layers = [
        _layer('prop', slot: ArtSlot.prop),
        _layer('bg', slot: ArtSlot.background),
        _layer('face', slot: ArtSlot.expression),
        _layer('body', slot: ArtSlot.base),
        _layer('fit', slot: ArtSlot.outfit),
      ];
      final scene = resolveArtScene(layers, moodId: 'happy');
      expect(scene.map((l) => l.slot).toList(), ArtSlot.values);
      expect(scene.map((l) => l.id).toList(), [
        'bg',
        'body',
        'fit',
        'face',
        'prop',
      ]);
    });

    test('slots with nothing drawn are simply skipped', () {
      final scene = resolveArtScene([
        _layer('body', slot: ArtSlot.base),
        _layer('face', slot: ArtSlot.expression),
      ], moodId: 'happy');
      expect(scene.map((l) => l.slot).toList(), [
        ArtSlot.base,
        ArtSlot.expression,
      ]);
    });

    test('slots whose layers all fail to match are skipped, and the rest '
        'of the scene still renders', () {
      final scene = resolveArtScene([
        _layer('body', slot: ArtSlot.base),
        _layer('party-hat', slot: ArtSlot.prop, moods: {'excited'}),
      ], moodId: 'sad');
      expect(scene.map((l) => l.id).toList(), ['body']);
    });

    test('no base layer means no scene at all — a floating outfit is worse '
        'than the kaomoji', () {
      final scene = resolveArtScene([
        _layer('bg', slot: ArtSlot.background),
        _layer('fit', slot: ArtSlot.outfit),
        _layer('face', slot: ArtSlot.expression),
      ], moodId: 'happy');
      expect(scene, isEmpty);
    });

    test('a base layer that does not fit the current mood also means no '
        'scene', () {
      final scene = resolveArtScene([
        _layer('sleepy-body', slot: ArtSlot.base, moods: {'sleepy'}),
        _layer('face', slot: ArtSlot.expression),
      ], moodId: 'happy');
      expect(scene, isEmpty);
    });

    test('no art at all is empty, not an error', () {
      expect(resolveArtScene(const [], moodId: 'happy'), isEmpty);
      expect(resolveArtScene(const []), isEmpty);
    });

    test('the whole wardrobe swaps together when the mood changes', () {
      final layers = [
        _layer('body-awake', slot: ArtSlot.base, isDefault: true),
        _layer('body-tucked-in', slot: ArtSlot.base, moods: {'sleepy'}),
        _layer('face-smile', slot: ArtSlot.expression, isDefault: true),
        _layer('face-zzz', slot: ArtSlot.expression, moods: {'sleepy'}),
        _layer('headphones', slot: ArtSlot.prop, ambient: {'music'}),
      ];

      expect(
        resolveArtScene(layers, moodId: 'happy').map((l) => l.id).toList(),
        ['body-awake', 'face-smile'],
      );
      expect(
        resolveArtScene(layers, moodId: 'sleepy').map((l) => l.id).toList(),
        ['body-tucked-in', 'face-zzz'],
      );
      expect(
        resolveArtScene(
          layers,
          moodId: 'happy',
          ambientKind: 'music',
        ).map((l) => l.id).toList(),
        ['body-awake', 'face-smile', 'headphones'],
      );
    });
  });

  group('ArtConditions.fromJson robustness', () {
    test('null, empty and blank parse to "matches anything"', () {
      expect(ArtConditions.fromJson(null), ArtConditions.any);
      expect(ArtConditions.fromJson(''), ArtConditions.any);
      expect(ArtConditions.fromJson('   '), ArtConditions.any);
      expect(ArtConditions.fromJson(const {}), ArtConditions.any);
    });

    test('garbage never throws — it degrades to "matches anything"', () {
      for (final junk in <Object?>[
        'not json at all',
        '{oh no',
        '[1, 2, 3]',
        42,
        3.14,
        true,
        ['moods'],
        const {'moods': 5, 'ambient': false, 'default': []},
      ]) {
        expect(
          ArtConditions.fromJson(junk),
          ArtConditions.any,
          reason: 'input: $junk',
        );
      }
    });

    test('a JSON string is decoded as readily as a decoded map — the field '
        'comes back either way', () {
      const encoded = '{"moods":["sleepy"],"ambient":["music"],"default":true}';
      final fromString = ArtConditions.fromJson(encoded);
      final fromMap = ArtConditions.fromJson(const {
        'moods': ['sleepy'],
        'ambient': ['music'],
        'default': true,
      });
      expect(fromString, fromMap);
      expect(fromString.moods, {'sleepy'});
      expect(fromString.ambient, {'music'});
      expect(fromString.isDefault, isTrue);
    });

    test('a bare string where a list was expected is taken as one value', () {
      final parsed = ArtConditions.fromJson(const {'moods': 'sleepy'});
      expect(parsed.moods, {'sleepy'});
    });

    test('junk elements are dropped, good ones kept', () {
      final parsed = ArtConditions.fromJson(const {
        'moods': ['sleepy', 1, null, '', '  cozy  ', true],
      });
      expect(parsed.moods, {'sleepy', 'cozy'});
    });

    test('"default" tolerates the shapes a hand-edited record might hold', () {
      expect(ArtConditions.fromJson(const {'default': true}).isDefault, isTrue);
      expect(
        ArtConditions.fromJson(const {'default': 'true'}).isDefault,
        isTrue,
      );
      expect(ArtConditions.fromJson(const {'default': 1}).isDefault, isTrue);
      expect(ArtConditions.fromJson(const {'default': 0}).isDefault, isFalse);
      expect(
        ArtConditions.fromJson(const {'default': 'nope'}).isDefault,
        isFalse,
      );
    });

    test('unknown mood ids are kept but simply never match', () {
      final parsed = ArtConditions.fromJson(const {
        'moods': ['not_a_real_mood'],
      });
      expect(parsed.moods, {'not_a_real_mood'});
      final layer = ArtLayer(
        id: 'x',
        coupleId: 'c',
        slot: ArtSlot.base,
        imageUrl: 'https://example.invalid/x.png',
        conditions: parsed,
      );
      expect(artLayerMatchScore(layer, moodId: 'happy'), isNull);
    });

    test('round-trips through toJson', () {
      const conditions = ArtConditions(
        moods: {'cozy', 'sleepy'},
        ambient: {'away'},
        isDefault: true,
      );
      expect(ArtConditions.fromJson(conditions.toJson()), conditions);
    });
  });

  group('ambient mapping', () {
    test('each ambient line kind maps onto an art ambient kind', () {
      AmbientLine line(AmbientLineKind kind) =>
          AmbientLine(kind: kind, text: 'x');

      expect(artAmbientKindFor(line(AmbientLineKind.nowPlaying)), 'music');
      expect(artAmbientKindFor(line(AmbientLineKind.activity)), 'activity');
      expect(artAmbientKindFor(line(AmbientLineKind.atComputer)), 'computer');
      expect(artAmbientKindFor(line(AmbientLineKind.onPhone)), 'phone');
      expect(artAmbientKindFor(line(AmbientLineKind.away)), 'away');
      // "probably asleep" folds into away — one drawing covers both.
      expect(artAmbientKindFor(line(AmbientLineKind.asleep)), 'away');
      expect(artAmbientKindFor(null), isNull);
    });

    test('every mapped kind is one the manager offers', () {
      for (final kind in AmbientLineKind.values) {
        final mapped = artAmbientKindFor(AmbientLine(kind: kind, text: 'x'));
        expect(artAmbientKinds, contains(mapped));
      }
    });
  });

  group('slot parsing and ordering', () {
    test('slot names round-trip, unknown names are rejected', () {
      for (final slot in ArtSlot.values) {
        expect(ArtSlot.tryParse(slot.name), slot);
      }
      expect(ArtSlot.tryParse('hat'), isNull);
      expect(ArtSlot.tryParse(null), isNull);
    });

    test('paint order is background first and prop last', () {
      expect(ArtSlot.values.first, ArtSlot.background);
      expect(ArtSlot.values.last, ArtSlot.prop);
      expect(ArtSlot.values, [
        ArtSlot.background,
        ArtSlot.base,
        ArtSlot.outfit,
        ArtSlot.expression,
        ArtSlot.prop,
      ]);
    });

    test('artLayersInSlot filters and orders for the manager list', () {
      final layers = [
        _layer('c', slot: ArtSlot.base, sort: 2),
        _layer('a', slot: ArtSlot.base, sort: 0),
        _layer('b', slot: ArtSlot.base, sort: 0),
        _layer('prop', slot: ArtSlot.prop, sort: 0),
      ];
      expect(artLayersInSlot(layers, ArtSlot.base).map((l) => l.id).toList(), [
        'a',
        'b',
        'c',
      ]);
      expect(artLayersInSlot(layers, ArtSlot.outfit), isEmpty);
    });
  });
}
