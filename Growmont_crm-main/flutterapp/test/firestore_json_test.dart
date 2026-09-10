import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/local/firestore_json.dart';

void main() {
  group('toJsonSafe', () {
    // NOTE: Timestamp.toDate() returns a local-time DateTime (a real
    // cloud_firestore SDK quirk, not something this codec controls), so
    // assertions compare moments-in-time via isAtSameMomentAs / DateTime
    // parsing rather than asserting an exact UTC-suffixed string.
    test('converts a top-level Timestamp to an ISO string of the same moment', () {
      final date = DateTime.utc(2026, 3, 1, 10, 30);
      final result = toJsonSafe({'date': Timestamp.fromDate(date)});

      expect(result['date'], isA<String>());
      expect(DateTime.parse(result['date'] as String).isAtSameMomentAs(date), isTrue);
    });

    test('recurses into nested maps', () {
      final date = DateTime.utc(2026, 1, 15);
      final result = toJsonSafe({
        'meta': {
          'created_at': Timestamp.fromDate(date),
          'label': 'x',
        },
      });

      expect(result['meta'], isA<Map>());
      final createdAt = (result['meta'] as Map)['created_at'] as String;
      expect(DateTime.parse(createdAt).isAtSameMomentAs(date), isTrue);
      expect((result['meta'] as Map)['label'], 'x');
    });

    test('recurses into a list of maps', () {
      final date = DateTime.utc(2026, 2, 2);
      final result = toJsonSafe({
        'items': [
          {'at': Timestamp.fromDate(date)},
          {'at': 'plain string'},
        ],
      });

      final items = result['items'] as List;
      final at = (items[0] as Map)['at'] as String;
      expect(DateTime.parse(at).isAtSameMomentAs(date), isTrue);
      expect((items[1] as Map)['at'], 'plain string');
    });

    test('drops a top-level FieldValue sentinel entirely', () {
      final result = toJsonSafe({
        'updated_at': FieldValue.serverTimestamp(),
        'name': 'Acme',
      });

      expect(result.containsKey('updated_at'), isFalse);
      expect(result['name'], 'Acme');
    });

    test('drops a FieldValue sentinel nested inside a map', () {
      final result = toJsonSafe({
        'meta': {
          'updated_at': FieldValue.serverTimestamp(),
          'label': 'x',
        },
      });

      final meta = result['meta'] as Map;
      expect(meta.containsKey('updated_at'), isFalse);
      expect(meta['label'], 'x');
    });

    test('passes through plain scalar values unchanged', () {
      final result = toJsonSafe({
        'name': 'Acme',
        'count': 5,
        'amount': 12.5,
        'active': true,
        'note': null,
      });

      expect(result['name'], 'Acme');
      expect(result['count'], 5);
      expect(result['amount'], 12.5);
      expect(result['active'], true);
      expect(result['note'], isNull);
    });
  });

  group('toFirestore', () {
    test('round-trips a Timestamp through toJsonSafe -> toFirestore', () {
      final date = DateTime.utc(2026, 3, 1, 10, 30);
      final iso = toJsonSafe({'date': Timestamp.fromDate(date)})['date'] as String;

      final back = toFirestore('sales', {'date': iso});

      expect(back['date'], isA<Timestamp>());
      expect((back['date'] as Timestamp).toDate().isAtSameMomentAs(date), isTrue);
    });

    test('unconditionally sets updated_at to a server timestamp sentinel', () {
      final result = toFirestore('clients', {'name': 'Acme', 'updated_at': 'stale'});

      expect(result['updated_at'], isA<FieldValue>());
    });

    test('only converts fields declared in kDateFields for that collection', () {
      final result = toFirestore('sales', {
        'date': '2026-03-01T00:00:00.000Z',
        'remarks': '2026-01-01T00:00:00.000Z', // date-shaped but not a date field
      });

      expect(result['date'], isA<Timestamp>());
      expect(result['remarks'], isA<String>());
    });

    test('leaves an unparseable date-field string untouched', () {
      final result = toFirestore('sales', {'date': ''});

      expect(result['date'], '');
    });
  });
}
