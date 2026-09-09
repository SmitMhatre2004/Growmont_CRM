import 'package:cloud_firestore/cloud_firestore.dart';

class Sale {
  const Sale({
    required this.id,
    required this.date,
    required this.clientName,
    required this.salesRep,
    this.salesRepName,
    this.salesRepId,
    required this.product,
    this.productDisplay,
    required this.company,
    required this.scheme,
    required this.amount,
    this.amountPaise = 0,
    required this.frequency,
    this.frequencyDisplay,
    this.remarks = '',
  });

  final String id;
  final String date;
  final String clientName;
  final String salesRep;
  final String? salesRepName;
  final String? salesRepId;
  final String product;
  final String? productDisplay;
  final String company;
  final String scheme;
  final String amount;
  final int amountPaise;
  final String frequency;
  final String? frequencyDisplay;
  final String remarks;

  factory Sale.fromJson(Map<String, dynamic> json, [String? docId]) {
    String dateStr = '';
    final rawDate = json['date'];
    if (rawDate is Timestamp) {
      dateStr = rawDate.toDate().toIso8601String().split('T').first;
    } else if (rawDate is String) {
      dateStr = rawDate;
    }

    int paise = 0;
    String rupeeStr = '0.00';
    if (json.containsKey('amount_paise') && json['amount_paise'] != null) {
      paise = (json['amount_paise'] as num).toInt();
      rupeeStr = (paise / 100).toStringAsFixed(2);
    } else if (json['amount'] != null) {
      final parsed = double.tryParse(json['amount'].toString()) ?? 0.0;
      paise = (parsed * 100).round();
      rupeeStr = parsed.toStringAsFixed(2);
    }

    final rep = (json['sales_rep_id'] ?? json['sales_rep'] ?? '').toString();

    return Sale(
      id: (docId ?? json['id'] ?? '').toString(),
      date: dateStr,
      clientName: json['client_name'] as String? ?? '',
      salesRep: rep,
      salesRepName: json['sales_rep_name'] as String?,
      salesRepId: rep,
      product: json['product'] as String? ?? '',
      productDisplay: json['product_display'] as String?,
      company: json['company'] as String? ?? '',
      scheme: json['scheme'] as String? ?? '',
      amount: rupeeStr,
      amountPaise: paise,
      frequency: json['frequency'] as String? ?? 'M',
      frequencyDisplay: json['frequency_display'] as String?,
      remarks: json['remarks'] as String? ?? '',
    );
  }

  factory Sale.fromFirestore(DocumentSnapshot doc) {
    return Sale.fromJson(doc.data() as Map<String, dynamic>? ?? {}, doc.id);
  }

  Map<String, dynamic> toFirestore() {
    final parsedRupees = double.tryParse(amount) ?? (amountPaise / 100);
    final paise = (parsedRupees * 100).round();

    return {
      'date': Timestamp.fromDate(DateTime.tryParse(date) ?? DateTime.now()),
      'client_name': clientName,
      'sales_rep_id': salesRep,
      if (salesRepName != null) 'sales_rep_name': salesRepName,
      'product': product,
      'company': company,
      'scheme': scheme,
      'amount_paise': paise,
      'frequency': frequency,
      'remarks': remarks,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toPayload() => {
    'date': date,
    'client_name': clientName,
    'sales_rep': salesRep,
    'product': product,
    'company': company,
    'scheme': scheme,
    'amount': amount,
    'amount_paise': amountPaise,
    'frequency': frequency,
    'remarks': remarks,
  };
}
