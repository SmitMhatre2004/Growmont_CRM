import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';

class FirestoreService {
  FirestoreService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    this.devUid,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  String? devUid;

  FirebaseStorage get storage => _storage;
  String? get currentUid => _auth.currentUser?.uid ?? devUid;

  // ----------------------------------------------------
  // Employees
  // ----------------------------------------------------

  Future<List<Employee>> getEmployees() async {
    final snapshot = await _firestore.collection('employees').orderBy('name').get();
    return snapshot.docs.map(Employee.fromFirestore).toList();
  }

  Future<Employee> getEmployee(dynamic id) async {
    final doc = await _firestore.collection('employees').doc(id.toString()).get();
    if (!doc.exists) {
      throw Exception('Employee not found');
    }
    return Employee.fromFirestore(doc);
  }

  Future<List<Client>> getEmployeeClients(dynamic id) async {
    final snapshot = await _firestore
        .collection('clients')
        .where('employee_ids', arrayContains: id.toString())
        .get();
    return snapshot.docs.map(Client.fromFirestore).toList();
  }

  Future<List<Sale>> getEmployeeSales(dynamic id) async {
    final snapshot = await _firestore
        .collection('sales')
        .where('sales_rep_id', isEqualTo: id.toString())
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs.map(Sale.fromFirestore).toList();
  }

  Future<List<EmployeeDropdown>> getEmployeesDropdown() async {
    final snapshot = await _firestore.collection('employees').orderBy('name').get();
    return snapshot.docs.map(EmployeeDropdown.fromFirestore).toList();
  }

  Future<void> createEmployee(Map<String, dynamic> data) async {
    // 1. Try Cloud Functions first (standard provisioning with custom role claims)
    try {
      final callable = _functions.httpsCallable('createEmployee');
      final res = await callable.call(data);
      if (res.data != null) return;
    } catch (_) {
      // Functions not deployed, unauthenticated, or network error. Fall through to direct provisioning.
    }

    // 2. Direct Auth & Firestore provisioning fallback
    String? newUid;
    final email = data['email']?.toString().trim();
    final password = data['password']?.toString();

    if (email != null && email.isNotEmpty && password != null && password.isNotEmpty) {
      try {
        final tempAppName = 'EmployeeProvisioning_${DateTime.now().millisecondsSinceEpoch}';
        final tempApp = await Firebase.initializeApp(
          name: tempAppName,
          options: Firebase.app().options,
        );
        try {
          final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
          final cred = await tempAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          newUid = cred.user?.uid;
        } finally {
          await tempApp.delete();
        }
      } catch (_) {
        // e.g. email already exists or auth offline; proceed to write doc in Firestore
      }
    }

    final docRef = newUid != null
        ? _firestore.collection('employees').doc(newUid)
        : _firestore.collection('employees').doc();

    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('password');
    if (cleanData['dob'] is String && (cleanData['dob'] as String).isNotEmpty) {
      final parsed = DateTime.tryParse(cleanData['dob'] as String);
      if (parsed != null) cleanData['dob'] = Timestamp.fromDate(parsed);
    }
    cleanData['role'] = (cleanData['role']?.toString().toUpperCase() == 'ADMIN') ? 'ADMIN' : 'EMPLOYEE';
    cleanData['avatar_url'] = cleanData['avatar_url'] ?? '';
    cleanData['clients_count'] = cleanData['clients_count'] ?? 0;
    cleanData['sales_count'] = cleanData['sales_count'] ?? 0;
    cleanData['interactions_count'] = cleanData['interactions_count'] ?? 0;
    cleanData['created_at'] = FieldValue.serverTimestamp();
    cleanData['updated_at'] = FieldValue.serverTimestamp();

    await docRef.set(cleanData, SetOptions(merge: true));
  }

  Future<void> updateEmployee(dynamic id, Map<String, dynamic> data) async {
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('password');
    if (cleanData['dob'] is String && (cleanData['dob'] as String).isNotEmpty) {
      final parsed = DateTime.tryParse(cleanData['dob'] as String);
      if (parsed != null) cleanData['dob'] = Timestamp.fromDate(parsed);
    }
    cleanData['updated_at'] = FieldValue.serverTimestamp();
    await _firestore.collection('employees').doc(id.toString()).update(cleanData);
  }

  Future<void> deleteEmployee(dynamic id) async {
    try {
      final callable = _functions.httpsCallable('deleteEmployee');
      await callable.call({'employeeId': id.toString()});
    } catch (_) {
      // Fallback: delete doc directly from Firestore
      await _firestore.collection('employees').doc(id.toString()).delete();
    }
  }

  // ----------------------------------------------------
  // Sales
  // ----------------------------------------------------

  Future<List<Sale>> getSales({String? salesRepId}) async {
    Query query = _firestore.collection('sales').orderBy('date', descending: true);
    if (salesRepId != null && salesRepId.isNotEmpty) {
      query = query.where('sales_rep_id', isEqualTo: salesRepId);
    }
    final snapshot = await query.get();
    return snapshot.docs.map(Sale.fromFirestore).toList();
  }

  Future<Sale> createSale(Map<String, dynamic> data) async {
    final docRef = _firestore.collection('sales').doc();
    final saleData = Map<String, dynamic>.from(data);

    // Ensure amount_paise is populated
    if (!saleData.containsKey('amount_paise') || saleData['amount_paise'] == null) {
      final rupeeVal = double.tryParse(saleData['amount']?.toString() ?? '0') ?? 0.0;
      saleData['amount_paise'] = (rupeeVal * 100).round();
    }
    saleData.remove('amount');

    // Convert date string to Timestamp
    if (saleData['date'] is String) {
      final parsed = DateTime.tryParse(saleData['date'] as String);
      if (parsed != null) saleData['date'] = Timestamp.fromDate(parsed);
    }

    // Ensure sales_rep_id
    if (saleData.containsKey('sales_rep')) {
      saleData['sales_rep_id'] = saleData.remove('sales_rep').toString();
    } else if (!saleData.containsKey('sales_rep_id') && currentUid != null) {
      saleData['sales_rep_id'] = currentUid;
    }

    saleData['created_at'] = FieldValue.serverTimestamp();
    saleData['updated_at'] = FieldValue.serverTimestamp();

    await docRef.set(saleData);
    final saved = await docRef.get();
    return Sale.fromFirestore(saved);
  }

  Future<Sale> updateSale(dynamic id, Map<String, dynamic> data) async {
    final docRef = _firestore.collection('sales').doc(id.toString());
    final saleData = Map<String, dynamic>.from(data);

    if (saleData.containsKey('amount')) {
      final rupeeVal = double.tryParse(saleData['amount']?.toString() ?? '0') ?? 0.0;
      saleData['amount_paise'] = (rupeeVal * 100).round();
      saleData.remove('amount');
    }

    if (saleData['date'] is String) {
      final parsed = DateTime.tryParse(saleData['date'] as String);
      if (parsed != null) saleData['date'] = Timestamp.fromDate(parsed);
    }

    if (saleData.containsKey('sales_rep')) {
      saleData['sales_rep_id'] = saleData.remove('sales_rep').toString();
    }

    saleData['updated_at'] = FieldValue.serverTimestamp();
    await docRef.update(saleData);
    final saved = await docRef.get();
    return Sale.fromFirestore(saved);
  }

  Future<void> deleteSale(dynamic id) async {
    await _firestore.collection('sales').doc(id.toString()).delete();
  }

  // ----------------------------------------------------
  // Interactions
  // ----------------------------------------------------

  Future<List<Interaction>> getInteractions({String? employeeId}) async {
    Query query = _firestore.collection('interactions').orderBy('date', descending: true);
    if (employeeId != null && employeeId.isNotEmpty) {
      query = query.where('employee_id', isEqualTo: employeeId);
    }
    final snapshot = await query.get();
    return snapshot.docs.map(Interaction.fromFirestore).toList();
  }

  Future<Interaction> createInteraction(Map<String, dynamic> data) async {
    final docRef = _firestore.collection('interactions').doc();
    final interData = Map<String, dynamic>.from(data);

    if (interData['date'] is String) {
      final parsed = DateTime.tryParse(interData['date'] as String);
      if (parsed != null) interData['date'] = Timestamp.fromDate(parsed);
    }
    if (interData['follow_up_date'] is String && (interData['follow_up_date'] as String).isNotEmpty) {
      final parsed = DateTime.tryParse(interData['follow_up_date'] as String);
      if (parsed != null) interData['follow_up_date'] = Timestamp.fromDate(parsed);
    }

    if (interData.containsKey('employee')) {
      interData['employee_id'] = interData.remove('employee').toString();
    } else if (!interData.containsKey('employee_id') && currentUid != null) {
      interData['employee_id'] = currentUid;
    }

    interData['created_at'] = FieldValue.serverTimestamp();
    interData['updated_at'] = FieldValue.serverTimestamp();

    await docRef.set(interData);
    final saved = await docRef.get();
    return Interaction.fromFirestore(saved);
  }

  Future<Interaction> updateInteraction(dynamic id, Map<String, dynamic> data) async {
    final docRef = _firestore.collection('interactions').doc(id.toString());
    final interData = Map<String, dynamic>.from(data);

    if (interData['date'] is String) {
      final parsed = DateTime.tryParse(interData['date'] as String);
      if (parsed != null) interData['date'] = Timestamp.fromDate(parsed);
    }
    if (interData['follow_up_date'] is String && (interData['follow_up_date'] as String).isNotEmpty) {
      final parsed = DateTime.tryParse(interData['follow_up_date'] as String);
      if (parsed != null) interData['follow_up_date'] = Timestamp.fromDate(parsed);
    }

    if (interData.containsKey('employee')) {
      interData['employee_id'] = interData.remove('employee').toString();
    }

    interData['updated_at'] = FieldValue.serverTimestamp();
    await docRef.update(interData);
    final saved = await docRef.get();
    return Interaction.fromFirestore(saved);
  }

  Future<void> deleteInteraction(dynamic id) async {
    await _firestore.collection('interactions').doc(id.toString()).delete();
  }

  // ----------------------------------------------------
  // Reminders
  // ----------------------------------------------------

  Future<List<Reminder>> getReminders() async {
    if (currentUid == null) return [];
    final snapshot = await _firestore
        .collection('reminders')
        .where('employee_id', isEqualTo: currentUid)
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs.map(Reminder.fromFirestore).toList();
  }

  Future<Reminder> createReminder(Map<String, dynamic> data) async {
    final docRef = _firestore.collection('reminders').doc();
    final remData = Map<String, dynamic>.from(data);

    if (remData['date'] is String) {
      final parsed = DateTime.tryParse(remData['date'] as String);
      if (parsed != null) remData['date'] = Timestamp.fromDate(parsed);
    }

    if (remData.containsKey('employee')) {
      remData['employee_id'] = remData.remove('employee').toString();
    } else if (!remData.containsKey('employee_id') && currentUid != null) {
      remData['employee_id'] = currentUid;
    }

    remData['is_sent'] = false;
    remData['created_at'] = FieldValue.serverTimestamp();
    remData['updated_at'] = FieldValue.serverTimestamp();

    await docRef.set(remData);
    final saved = await docRef.get();
    return Reminder.fromFirestore(saved);
  }

  Future<Reminder> updateReminder(dynamic id, Map<String, dynamic> data) async {
    final docRef = _firestore.collection('reminders').doc(id.toString());
    final remData = Map<String, dynamic>.from(data);

    if (remData['date'] is String) {
      final parsed = DateTime.tryParse(remData['date'] as String);
      if (parsed != null) remData['date'] = Timestamp.fromDate(parsed);
    }

    if (remData.containsKey('employee')) {
      remData['employee_id'] = remData.remove('employee').toString();
    }

    remData['updated_at'] = FieldValue.serverTimestamp();
    await docRef.update(remData);
    final saved = await docRef.get();
    return Reminder.fromFirestore(saved);
  }

  Future<void> deleteReminder(dynamic id) async {
    await _firestore.collection('reminders').doc(id.toString()).delete();
  }

  // ----------------------------------------------------
  // Auth & Profile
  // ----------------------------------------------------

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No authenticated user found');
    }

    // Reauthenticate
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: oldPassword,
    );
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  // ----------------------------------------------------
  // Excel Cloud Functions
  // ----------------------------------------------------

  Future<String> exportSalesExcel({String? salesRepId}) async {
    final callable = _functions.httpsCallable('exportSalesExcel');
    final result = await callable.call({'sales_rep_id': salesRepId});
    return result.data['base64'] as String;
  }

  Future<String> exportInteractionsExcel({String? employeeId}) async {
    final callable = _functions.httpsCallable('exportInteractionsExcel');
    final result = await callable.call({'employee_id': employeeId});
    return result.data['base64'] as String;
  }

  Future<int> importSales(String base64) async {
    final callable = _functions.httpsCallable('importSalesExcel');
    final result = await callable.call({'base64': base64});
    return (result.data['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> importInteractions(String base64) async {
    final callable = _functions.httpsCallable('importInteractionsExcel');
    final result = await callable.call({'base64': base64});
    return (result.data['count'] as num?)?.toInt() ?? 0;
  }
}
