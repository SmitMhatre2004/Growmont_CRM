/// A short note (one bullet) about a client, written by an employee or admin.
///
/// Stored in the top-level `client_notes` collection. `client_owner_id` is the
/// client's assigned employee at the time of writing (kept current when the
/// client is transferred); it lets owner-scoped sync and the security rules
/// work the same way they do for interactions.
class ClientNote {
  const ClientNote({
    required this.id,
    required this.clientId,
    required this.clientOwnerId,
    required this.text,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
  });

  static const int maxLength = 500;

  final String id;
  final String clientId;
  final String clientOwnerId;
  final String text;
  final String authorId;
  final String authorName;
  final DateTime createdAt;

  /// Returns the trimmed text if it is a valid note (1-500 chars after
  /// trimming), otherwise null.
  static String? validate(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  factory ClientNote.fromJson(Map<String, dynamic> json, [String? docId]) {
    final rawCreated = json['created_at'];
    DateTime created;
    if (rawCreated is DateTime) {
      created = rawCreated;
    } else if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }
    return ClientNote(
      id: (docId ?? json['id'] ?? '').toString(),
      clientId: (json['client_id'] ?? '').toString(),
      clientOwnerId: (json['client_owner_id'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      authorId: (json['author_id'] ?? '').toString(),
      authorName: (json['author_name'] ?? '').toString(),
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'client_owner_id': clientOwnerId,
    'text': text,
    'author_id': authorId,
    'author_name': authorName,
    'created_at': createdAt.toIso8601String(),
  };
}
