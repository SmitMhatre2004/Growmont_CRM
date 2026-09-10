// lib/core/local/payload_normalizer.dart
//
// Applies the same field normalization FirestoreService did inline before
// writing, so a locally-written document is byte-identical (modulo the
// timestamp fields toFirestore() converts on push) to what the server
// would have stored. Rules are transcribed from firestore_service.dart —
// if you change one there, check this file too, and vice versa.

class PayloadNormalizer {
  PayloadNormalizer._();

  static Map<String, dynamic> forCollection(
    String collection,
    Map<String, dynamic> input, {
    required bool isCreate,
    String? currentUid,
  }) {
    final data = Map<String, dynamic>.from(input);
    final now = DateTime.now().toUtc().toIso8601String();

    switch (collection) {
      case 'sales':
        _normalizeSale(data, isCreate: isCreate, currentUid: currentUid);
        break;
      case 'interactions':
        _normalizeInteraction(data, isCreate: isCreate, currentUid: currentUid);
        break;
      case 'reminders':
        _normalizeReminder(data, isCreate: isCreate, currentUid: currentUid);
        break;
      case 'employees':
        _normalizeEmployee(data);
        break;
      case 'clients':
        // No collection-specific normalization beyond timestamps below.
        break;
    }

    if (isCreate) {
      data['created_at'] = now;
    }
    // FirestoreJson.toFirestore replaces this with
    // FieldValue.serverTimestamp() at push time — the local value only
    // needs to be good enough for local sorting before the first push.
    data['updated_at'] = now;

    return data;
  }

  // From FirestoreService.createSale / updateSale.
  static void _normalizeSale(
    Map<String, dynamic> data, {
    required bool isCreate,
    String? currentUid,
  }) {
    final amountPaiseMissing =
        !data.containsKey('amount_paise') || data['amount_paise'] == null;
    if (data.containsKey('amount') || (isCreate && amountPaiseMissing)) {
      final rupees = double.tryParse(data['amount']?.toString() ?? '0') ?? 0.0;
      data['amount_paise'] = (rupees * 100).round();
    }
    data.remove('amount');

    if (data.containsKey('sales_rep')) {
      data['sales_rep_id'] = data.remove('sales_rep').toString();
    } else if (isCreate && !data.containsKey('sales_rep_id') && currentUid != null) {
      data['sales_rep_id'] = currentUid;
    }
  }

  // From FirestoreService.createInteraction / updateInteraction.
  static void _normalizeInteraction(
    Map<String, dynamic> data, {
    required bool isCreate,
    String? currentUid,
  }) {
    if (data.containsKey('employee')) {
      data['employee_id'] = data.remove('employee').toString();
    } else if (isCreate && !data.containsKey('employee_id') && currentUid != null) {
      data['employee_id'] = currentUid;
    }
  }

  // From FirestoreService.createReminder / updateReminder.
  static void _normalizeReminder(
    Map<String, dynamic> data, {
    required bool isCreate,
    String? currentUid,
  }) {
    if (data.containsKey('employee')) {
      data['employee_id'] = data.remove('employee').toString();
    } else if (isCreate && !data.containsKey('employee_id') && currentUid != null) {
      data['employee_id'] = currentUid;
    }
    if (isCreate) {
      data['is_sent'] = false;
    }
  }

  // From FirestoreService.updateEmployee. A password must never reach
  // SQLite — always stripped, on both create and update.
  static void _normalizeEmployee(Map<String, dynamic> data) {
    data.remove('password');
  }
}
