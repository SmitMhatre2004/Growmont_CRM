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
    required this.frequency,
    this.frequencyDisplay,
    this.remarks = '',
  });

  final int id;
  final String date;
  final String clientName;
  final int salesRep;
  final String? salesRepName;
  final int? salesRepId;
  final String product;
  final String? productDisplay;
  final String company;
  final String scheme;
  final String amount;
  final String frequency;
  final String? frequencyDisplay;
  final String remarks;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as int,
      date: json['date'] as String,
      clientName: json['client_name'] as String? ?? '',
      salesRep: json['sales_rep'] as int,
      salesRepName: json['sales_rep_name'] as String?,
      salesRepId: json['sales_rep_id'] as int?,
      product: json['product'] as String? ?? '',
      productDisplay: json['product_display'] as String?,
      company: json['company'] as String? ?? '',
      scheme: json['scheme'] as String? ?? '',
      amount: json['amount'].toString(),
      frequency: json['frequency'] as String? ?? 'M',
      frequencyDisplay: json['frequency_display'] as String?,
      remarks: json['remarks'] as String? ?? '',
    );
  }

  Map<String, dynamic> toPayload() => {
        'date': date,
        'client_name': clientName,
        'sales_rep': salesRep,
        'product': product,
        'company': company,
        'scheme': scheme,
        'amount': amount,
        'frequency': frequency,
        'remarks': remarks,
      };
}
