import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/models/client.dart';
import 'package:growmont_crm/models/employee.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/sale.dart';

void main() {
  group('Employee counts calculation', () {
    test('Employee.copyWith preserves and updates counts', () {
      const emp = Employee(
        id: 'emp_1',
        name: 'Samir Joshi',
        email: 'samir@growmont.com',
        mobileNo: '9920995088',
        gender: 'M',
        dob: '1990-01-01',
        role: 'ADMIN',
        clientsCount: 0,
        salesCount: 0,
        interactionsCount: 0,
      );

      final updated = emp.copyWith(
        clientsCount: 8,
        salesCount: 15,
        interactionsCount: 23,
      );

      expect(updated.clientsCount, equals(8));
      expect(updated.salesCount, equals(15));
      expect(updated.interactionsCount, equals(23));
      expect(updated.name, equals('Samir Joshi'));
    });

    test('Counts match by employeeId and employeeName', () {
      const emp = Employee(
        id: 'emp_1',
        name: 'Samir Joshi',
        email: 'samir@growmont.com',
        mobileNo: '9920995088',
        gender: 'M',
        dob: '1990-01-01',
        role: 'ADMIN',
      );

      final clients = [
        const Client(id: 'c1', name: 'Client 1', contactNumber: '123', employeeId: 'emp_1'),
        const Client(id: 'c2', name: 'Client 2', contactNumber: '456', employeeName: 'Samir Joshi'),
        const Client(id: 'c3', name: 'Client 3', contactNumber: '789', employeeId: 'other'),
      ];

      final sales = [
        const Sale(
          id: 's1',
          date: '2026-09-01',
          clientName: 'Client 1',
          salesRep: 'emp_1',
          salesRepId: 'emp_1',
          product: 'MF',
          company: 'HDFC',
          scheme: 'Equity',
          amount: '10000',
          frequency: 'M',
        ),
        const Sale(
          id: 's2',
          date: '2026-09-02',
          clientName: 'Client 2',
          salesRep: 'Samir Joshi',
          salesRepName: 'Samir Joshi',
          product: 'HI',
          company: 'Star',
          scheme: 'Care',
          amount: '5000',
          frequency: 'A',
        ),
      ];

      final interactions = [
        const Interaction(
          id: 'i1',
          date: '2026-09-01',
          clientName: 'Client 1',
          clientContact: '123',
          employee: 'emp_1',
          employeeId: 'emp_1',
          followUpDate: '2026-09-10',
          followUpTime: '10:00',
          priority: 'HIGH',
        ),
        const Interaction(
          id: 'i2',
          date: '2026-09-02',
          clientName: 'Client 2',
          clientContact: '456',
          employee: 'Samir Joshi',
          employeeName: 'Samir Joshi',
          followUpDate: '2026-09-11',
          followUpTime: '11:00',
          priority: 'MEDIUM',
        ),
        const Interaction(
          id: 'i3',
          date: '2026-09-03',
          clientName: 'Client 3',
          clientContact: '789',
          employee: 'emp_1',
          followUpDate: '',
          followUpTime: '',
          priority: 'LOW',
        ),
      ];

      final clientCount = clients.where((c) =>
        (c.employeeId.isNotEmpty && c.employeeId == emp.id) ||
        (c.employeeName != null && c.employeeName!.toLowerCase() == emp.name.toLowerCase())
      ).length;

      final saleCount = sales.where((s) =>
        (s.salesRepId != null && s.salesRepId == emp.id) ||
        s.salesRep == emp.id ||
        (s.salesRepName != null && s.salesRepName!.toLowerCase() == emp.name.toLowerCase()) ||
        s.salesRep.toLowerCase() == emp.name.toLowerCase()
      ).length;

      final chatCount = interactions.where((i) =>
        (i.employeeId != null && i.employeeId == emp.id) ||
        i.employee == emp.id ||
        (i.employeeName != null && i.employeeName!.toLowerCase() == emp.name.toLowerCase()) ||
        i.employee.toLowerCase() == emp.name.toLowerCase()
      ).length;

      expect(clientCount, equals(2));
      expect(saleCount, equals(2));
      expect(chatCount, equals(3));
    });
  });
}
