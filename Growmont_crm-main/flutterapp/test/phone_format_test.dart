// test/phone_format_test.dart
//
// Money formatting for the phone Reports screens.

import 'package:flutter_test/flutter_test.dart';
import 'package:growmont_crm/features/reports/phone/phone_style.dart';

void main() {
  test('compactMoney keeps one decimal for K, L and Cr', () {
    expect(compactMoney(60000000), '₹6.0L');
    expect(compactMoney(30000000), '₹3.0L');
    expect(compactMoney(7550000), '₹75.5K');
    expect(compactMoney(1200000000), '₹1.2Cr');
    expect(compactMoney(85000), '₹850');
    expect(compactMoney(0), '₹0');
  });

  test('rounding up into the next unit does not print 100.0K', () {
    expect(compactMoney(9999900), '₹1.0L');
    expect(compactMoney(999990000), '₹1.0Cr');
  });
}
