class Client {
  const Client({
    required this.id,
    required this.name,
    required this.contactNumber,
  });

  final int id;
  final String name;
  final String contactNumber;

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id'] as int,
      name: json['name'] as String,
      contactNumber: json['contact_number'] as String? ?? '',
    );
  }
}
