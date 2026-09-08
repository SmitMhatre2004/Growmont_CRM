import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/models/interaction.dart';
import 'package:growmont_crm/models/reminder.dart';
import 'package:growmont_crm/models/sale.dart';

void main() {
  group('Dashboard Sorting Tests', () {
    DateTime? parseDateTime(String? dateStr, [String? timeStr]) {
      if (dateStr == null || dateStr.trim().isEmpty) return null;
      final d = DateTime.tryParse(dateStr.trim());
      if (d == null) return null;
      if (timeStr != null && timeStr.trim().isNotEmpty) {
        final parts = timeStr.trim().split(':');
        if (parts.isNotEmpty) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
          final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
          return DateTime(d.year, d.month, d.day, h, m, s);
        }
      }
      return DateTime(d.year, d.month, d.day);
    }

    int priorityWeight(String priority) {
      switch (priority.toUpperCase()) {
        case 'HIGH':
          return 3;
        case 'MEDIUM':
          return 2;
        case 'LOW':
          return 1;
        default:
          return 0;
      }
    }

    int compareUpcomingDate(DateTime? dtA, DateTime? dtB, DateTime todayStart) {
      if (dtA == null && dtB == null) return 0;
      if (dtA == null) return 1;
      if (dtB == null) return -1;

      final isUpcomingA = !dtA.isBefore(todayStart);
      final isUpcomingB = !dtB.isBefore(todayStart);

      if (isUpcomingA && !isUpcomingB) return -1;
      if (!isUpcomingA && isUpcomingB) return 1;

      if (isUpcomingA && isUpcomingB) {
        return dtA.compareTo(dtB);
      } else {
        return dtB.compareTo(dtA);
      }
    }

    test('Upcoming follow-ups sort soonest upcoming first', () {
      final now = DateTime(2026, 9, 9, 12, 0);
      final todayStart = DateTime(now.year, now.month, now.day);

      final interactions = [
        Interaction(
          id: '1',
          date: '2026-09-01',
          clientName: 'Future Client 2',
          clientContact: '111',
          employee: 'emp1',
          followUpDate: '2026-09-15',
          followUpTime: '10:00:00',
          priority: 'MEDIUM',
        ),
        Interaction(
          id: '2',
          date: '2026-09-01',
          clientName: 'Today Client Later',
          clientContact: '222',
          employee: 'emp1',
          followUpDate: '2026-09-09',
          followUpTime: '15:00:00',
          priority: 'HIGH',
        ),
        Interaction(
          id: '3',
          date: '2026-09-01',
          clientName: 'Today Client Earlier',
          clientContact: '333',
          employee: 'emp1',
          followUpDate: '2026-09-09',
          followUpTime: '09:00:00',
          priority: 'LOW',
        ),
        Interaction(
          id: '4',
          date: '2026-09-01',
          clientName: 'Tomorrow Client',
          clientContact: '444',
          employee: 'emp1',
          followUpDate: '2026-09-10',
          followUpTime: '11:00:00',
          priority: 'HIGH',
        ),
        Interaction(
          id: '5',
          date: '2026-08-01',
          clientName: 'Past Client Yesterday',
          clientContact: '555',
          employee: 'emp1',
          followUpDate: '2026-09-08',
          followUpTime: '10:00:00',
          priority: 'HIGH',
        ),
      ];

      interactions.sort((a, b) {
        final dtA = parseDateTime(a.followUpDate, a.followUpTime);
        final dtB = parseDateTime(b.followUpDate, b.followUpTime);
        final cmp = compareUpcomingDate(dtA, dtB, todayStart);
        if (cmp != 0) return cmp;
        final pwA = priorityWeight(a.priority);
        final pwB = priorityWeight(b.priority);
        if (pwA != pwB) return pwB.compareTo(pwA);
        return a.clientName.toLowerCase().compareTo(b.clientName.toLowerCase());
      });

      expect(interactions[0].clientName, 'Today Client Earlier');
      expect(interactions[1].clientName, 'Today Client Later');
      expect(interactions[2].clientName, 'Tomorrow Client');
      expect(interactions[3].clientName, 'Future Client 2');
      expect(interactions[4].clientName, 'Past Client Yesterday');
    });

    test('Recent sales sort with newest date at the top', () {
      final sales = [
        const Sale(
          id: '1',
          date: '2026-08-20',
          clientName: 'Old Sale',
          salesRep: 'rep1',
          product: 'MF',
          company: 'HDFC',
          scheme: 'Equity',
          amount: '1000',
          frequency: 'M',
        ),
        const Sale(
          id: '2',
          date: '2026-09-08',
          clientName: 'Yesterday Sale',
          salesRep: 'rep1',
          product: 'MF',
          company: 'ICICI',
          scheme: 'Prudential',
          amount: '5000',
          frequency: 'M',
        ),
        const Sale(
          id: '3',
          date: '2026-09-09',
          clientName: 'Today Sale',
          salesRep: 'rep1',
          product: 'MF',
          company: 'SBI',
          scheme: 'Bluechip',
          amount: '10000',
          frequency: 'M',
        ),
      ];

      sales.sort((a, b) {
        final da = parseDateTime(a.date);
        final db = parseDateTime(b.date);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        final cmp = db.compareTo(da);
        if (cmp != 0) return cmp;
        final idA = int.tryParse(a.id);
        final idB = int.tryParse(b.id);
        if (idA != null && idB != null) {
          return idB.compareTo(idA);
        }
        return b.id.compareTo(a.id);
      });

      expect(sales[0].clientName, 'Today Sale');
      expect(sales[1].clientName, 'Yesterday Sale');
      expect(sales[2].clientName, 'Old Sale');
    });

    test('Reminders sort with most upcoming at the top', () {
      final now = DateTime(2026, 9, 9, 12, 0);
      final todayStart = DateTime(now.year, now.month, now.day);

      final reminders = [
        const Reminder(
          id: 'r1',
          employee: 'e1',
          eventName: 'Next Week Meeting',
          type: 'CORPORATE',
          priority: 'MEDIUM',
          date: '2026-09-16',
          time: '11:00:00',
        ),
        const Reminder(
          id: 'r2',
          employee: 'e1',
          eventName: 'Today Afternoon Review',
          type: 'CORPORATE',
          priority: 'HIGH',
          date: '2026-09-09',
          time: '14:00:00',
        ),
        const Reminder(
          id: 'r3',
          employee: 'e1',
          eventName: 'Tomorrow Morning Standup',
          type: 'CORPORATE',
          priority: 'LOW',
          date: '2026-09-10',
          time: '09:30:00',
        ),
      ];

      reminders.sort((a, b) {
        final dtA = parseDateTime(a.date, a.time);
        final dtB = parseDateTime(b.date, b.time);
        final cmp = compareUpcomingDate(dtA, dtB, todayStart);
        if (cmp != 0) return cmp;
        final pwA = priorityWeight(a.priority);
        final pwB = priorityWeight(b.priority);
        if (pwA != pwB) return pwB.compareTo(pwA);
        return a.eventName.toLowerCase().compareTo(b.eventName.toLowerCase());
      });

      expect(reminders[0].eventName, 'Today Afternoon Review');
      expect(reminders[1].eventName, 'Tomorrow Morning Standup');
      expect(reminders[2].eventName, 'Next Week Meeting');
    });
  });
}
