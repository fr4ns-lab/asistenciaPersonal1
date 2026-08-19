import 'package:asistenciapersonal1/models/admin_directory_user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminUserDirectoryPage {
  const AdminUserDirectoryPage({
    required this.users,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<AdminDirectoryUser> users;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;
}

class AdminUserDirectoryService {
  AdminUserDirectoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  // El directorio actual tiene alrededor de 200 usuarios. Mantiene una sola
  // carga inicial sin impedir la paginación si la colección crece.
  static const pageSize = 250;

  final FirebaseFirestore _firestore;

  Future<AdminUserDirectoryPage> getUsers({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('dni_by_email')
        .orderBy(FieldPath.documentId)
        .limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final users = snapshot.docs
        .map(
          (document) => AdminDirectoryUser.fromFirestore(
            documentId: document.id,
            data: document.data(),
          ),
        )
        .toList(growable: false);

    return AdminUserDirectoryPage(
      users: users,
      lastDocument: snapshot.docs.isEmpty ? startAfter : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }
}
