import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/core/local/payload_normalizer.dart';

void main() {
  group('sales', () {
    test('converts a decimal rupee amount to integer paise', () {
      final result = PayloadNormalizer.forCollection(
        'sales',
        {'amount': '1234.56'},
        isCreate: true,
      );
      expect(result['amount_paise'], 123456);
      expect(result.containsKey('amount'), isFalse);
    });

    test('moves sales_rep to sales_rep_id', () {
      final result = PayloadNormalizer.forCollection(
        'sales',
        {'sales_rep': 'user_1'},
        isCreate: true,
      );
      expect(result['sales_rep_id'], 'user_1');
      expect(result.containsKey('sales_rep'), isFalse);
    });

    test('defaults sales_rep_id to currentUid on create when absent', () {
      final result = PayloadNormalizer.forCollection(
        'sales',
        {'amount_paise': 100},
        isCreate: true,
        currentUid: 'me',
      );
      expect(result['sales_rep_id'], 'me');
    });

    test('does not touch amount_paise on update when amount key is absent', () {
      final result = PayloadNormalizer.forCollection(
        'sales',
        {'remarks': 'updated'},
        isCreate: false,
      );
      expect(result.containsKey('amount_paise'), isFalse);
    });
  });

  group('interactions', () {
    test('moves employee to employee_id', () {
      final result = PayloadNormalizer.forCollection(
        'interactions',
        {'employee': 'user_2'},
        isCreate: true,
      );
      expect(result['employee_id'], 'user_2');
      expect(result.containsKey('employee'), isFalse);
    });
  });

  group('reminders', () {
    test('moves employee to employee_id', () {
      final result = PayloadNormalizer.forCollection(
        'reminders',
        {'employee': 'user_3'},
        isCreate: true,
      );
      expect(result['employee_id'], 'user_3');
    });

    test('sets is_sent false on create', () {
      final result = PayloadNormalizer.forCollection(
        'reminders',
        {},
        isCreate: true,
      );
      expect(result['is_sent'], false);
    });

    test('does not set is_sent on update', () {
      final result = PayloadNormalizer.forCollection(
        'reminders',
        {},
        isCreate: false,
      );
      expect(result.containsKey('is_sent'), isFalse);
    });
  });

  group('employees', () {
    test('strips password on create', () {
      final result = PayloadNormalizer.forCollection(
        'employees',
        {'name': 'Amit', 'password': 'secret123'},
        isCreate: true,
      );
      expect(result.containsKey('password'), isFalse);
      expect(result['name'], 'Amit');
    });

    test('strips password on update', () {
      final result = PayloadNormalizer.forCollection(
        'employees',
        {'password': 'secret123'},
        isCreate: false,
      );
      expect(result.containsKey('password'), isFalse);
    });
  });

  group('timestamps', () {
    test('sets created_at only on create', () {
      final created = PayloadNormalizer.forCollection('clients', {}, isCreate: true);
      final updated = PayloadNormalizer.forCollection('clients', {}, isCreate: false);
      expect(created.containsKey('created_at'), isTrue);
      expect(updated.containsKey('created_at'), isFalse);
    });

    test('always sets updated_at', () {
      final created = PayloadNormalizer.forCollection('clients', {}, isCreate: true);
      final updated = PayloadNormalizer.forCollection('clients', {}, isCreate: false);
      expect(created.containsKey('updated_at'), isTrue);
      expect(updated.containsKey('updated_at'), isTrue);
    });
  });
}
