import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/employee.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/reminder.dart';
import 'package:growmont_crm/models/sale.dart';
import 'package:growmont_crm/models/user.dart';

void main() {
  group('Firestore Models & Money Handling Tests', () {
    test('Sale handles integer paise correctly', () {
      final sale = Sale.fromJson({
        'id': 'sale_1',
        'date': '2026-03-01',
        'client_name': 'Acme Corp',
        'sales_rep_id': 'user_3',
        'sales_rep_name': 'Samir Joshi',
        'product': 'MF',
        'company': 'HDFC',
        'scheme': 'Top 100',
        'amount_paise': 2000050, // ₹20,000.50
        'frequency': 'M',
        'remarks': 'Test sale',
      });

      expect(sale.id, 'sale_1');
      expect(sale.amountPaise, 2000050);
      expect(sale.amount, '20000.50');
      expect(sale.salesRep, 'user_3');

      final firestoreMap = sale.toFirestore();
      expect(firestoreMap['amount_paise'], 2000050);
      expect(firestoreMap['client_name'], 'Acme Corp');
      expect(firestoreMap['sales_rep_id'], 'user_3');
      expect(firestoreMap['date'], isA<Timestamp>());
    });

    test('Sale falls back gracefully when given rupee string', () {
      final sale = Sale.fromJson({
        'id': 'sale_legacy',
        'date': '2026-03-01',
        'client_name': 'Legacy Client',
        'sales_rep': 'user_2',
        'product': 'HI',
        'amount': '5000.00',
        'frequency': 'Y',
      });

      expect(sale.amountPaise, 500000);
      expect(sale.amount, '5000.00');
    });

    test('Employee model converts fields and dates correctly', () {
      final now = DateTime(1995, 5, 20);
      final employee = Employee.fromJson({
        'id': 'user_6',
        'name': 'Admin User',
        'email': 'admin@growmont.com',
        'mobile_no': '9876543210',
        'gender': 'M',
        'dob': Timestamp.fromDate(now),
        'role': 'ADMIN',
        'clients_count': 5,
        'sales_count': 12,
        'interactions_count': 8,
      });

      expect(employee.id, 'user_6');
      expect(employee.role, 'ADMIN');
      expect(employee.genderDisplay, 'Male');
      expect(employee.dob, '1995-05-20');
      expect(employee.clientsCount, 5);
      expect(employee.initials, 'AU');
    });

    test('Employee initials tolerate messy names', () {
      Employee named(String name) => Employee.fromJson({'id': 'e1', 'name': name});

      expect(named('Soham Patil').initials, 'SP');
      expect(named('Suraj').initials, 'S');
      // Blank segments used to throw a RangeError on name.split(' ')[0].
      expect(named('  Ravi   Kumar Shah ').initials, 'RK');
      expect(named('').initials, '?');
      expect(named('   ').initials, '?');
    });

    test('Client model parses employee_ids array', () {
      final client = Client.fromJson({
        'id': 'client_1',
        'name': 'Sneha',
        'contact_number': '1234567890',
        'employee_ids': ['user_1', 'user_4'],
      });

      expect(client.id, 'client_1');
      expect(client.employeeIds, ['user_1', 'user_4']);

      final map = client.toFirestore();
      expect(map['employee_ids'], ['user_1', 'user_4']);
    });

    test('Interaction model parses and outputs timestamps', () {
      final inter = Interaction.fromJson({
        'id': 'inter_1',
        'date': '2026-03-05',
        'client_name': 'Test Client',
        'client_contact': '9998887776',
        'employee_id': 'user_3',
        'employee_name': 'Samir Joshi',
        'follow_up_date': '2026-03-15',
        'follow_up_time': '14:30',
        'priority': 'HIGH',
        'discussion_notes': 'Discussed mutual funds',
      });

      expect(inter.id, 'inter_1');
      expect(inter.employee, 'user_3');
      expect(inter.priority, 'HIGH');

      final map = inter.toFirestore();
      expect(map['date'], isA<Timestamp>());
      expect(map['follow_up_date'], isA<Timestamp>());
      expect(map['follow_up_time'], '14:30:00');
    });

    test('Reminder model parses and sets is_sent false by default', () {
      final rem = Reminder.fromJson({
        'id': 'rem_1',
        'employee_id': 'user_3',
        'event_name': 'Portfolio Review',
        'type': 'CORPORATE',
        'priority': 'HIGH',
        'date': '2026-03-20',
        'time': '11:00',
        'description': 'Quarterly review',
        'repeat_days': ['Mon', 'Fri'],
      });

      expect(rem.id, 'rem_1');
      expect(rem.repeatDays, ['Mon', 'Fri']);

      final map = rem.toFirestore();
      expect(map['is_sent'], false);
      expect(map['time'], '11:00:00');
      expect(map['date'], isA<Timestamp>());
    });

    test('AppUser model handles roles and initials', () {
      final adminUser = AppUser.fromJson({
        'id': 'user_6',
        'name': 'Soham Patil',
        'email': 'admin@growmont.com',
        'role': 'ADMIN',
      });

      expect(adminUser.id, 'user_6');
      expect(adminUser.isAdmin, true);
      expect(adminUser.initials, 'SP');

      final empUser = AppUser.fromJson({
        'id': 'user_2',
        'name': 'Suraj',
        'email': 'suraj@growmont.com',
        'role': 'EMPLOYEE',
      });

      expect(empUser.isAdmin, false);
      expect(empUser.initials, 'S');
    });
  });
}
