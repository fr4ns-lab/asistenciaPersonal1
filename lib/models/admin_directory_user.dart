class AdminDirectoryUser {
  const AdminDirectoryUser({
    required this.email,
    required this.dni,
    required this.name,
  });

  final String email;
  final String dni;
  final String name;

  factory AdminDirectoryUser.fromFirestore({
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return AdminDirectoryUser(
      email: documentId.trim().toLowerCase(),
      dni: _value(data['dni']),
      name: _value(data['name'] ?? data['nombre']),
    );
  }

  bool get hasDni => dni.isNotEmpty;

  String get displayName => name.isEmpty ? 'Sin nombre registrado' : name;
}

String _value(Object? value) => value?.toString().trim() ?? '';
