import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/features/auth/auth_provider.dart';
import 'package:growmont_crm/features/employees/employees_excel.dart';

void main() {
  group('Auth Gate & Domain Eligibility Tests', () {
    test('kAllowedEmailDomain is @growmont.com', () {
      expect(kAllowedEmailDomain, '@growmont.com');
    });

    test('employeeImportPayload requires @growmont.com domain', () {
      final validRow = [
        'Rohan Sharma',
        'rohan@growmont.com',
        '9876543210',
        'M',
        '1995-05-15',
        'EMPLOYEE',
        'Pass@123',
      ];
      final invalidRow = [
        'Jane Doe',
        'jane@gmail.com',
        '9876543210',
        'F',
        '1996-06-16',
        'EMPLOYEE',
        'Pass@123',
      ];
      final invalidSubdomainRow = [
        'Attacker',
        'attacker@growmont.com.fake.org',
        '9876543210',
        'O',
        '1997-07-17',
        'EMPLOYEE',
        'Pass@123',
      ];

      final validPayload = employeeImportPayload(validRow);
      expect(validPayload, isNotNull);
      expect(validPayload!['email'], 'rohan@growmont.com');

      final invalidPayload = employeeImportPayload(invalidRow);
      expect(invalidPayload, isNull);

      final invalidSubdomainPayload = employeeImportPayload(invalidSubdomainRow);
      expect(invalidSubdomainPayload, isNull);
    });
  });
}
