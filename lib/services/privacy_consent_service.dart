// lib/services/privacy_consent_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PrivacyConsentService {
  PrivacyConsentService._();
  static final PrivacyConsentService instance = PrivacyConsentService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _userDocIdFromEmail(String email) {
    return email.toLowerCase().trim().split('@').first;
  }

  Future<bool> hasAcceptedConsent(User user) async {
    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) return false;

    final docId = _userDocIdFromEmail(email);
    final doc = await _db.collection('users').doc(docId).get();

    if (!doc.exists) return false;

    final data = doc.data();
    if (data == null) return false;

    return (data['privacyConsentAccepted'] ?? false) == true;
  }

  Future<void> saveConsent(User user) async {
    final email = user.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      throw Exception('El usuario no tiene correo válido.');
    }

    final docId = _userDocIdFromEmail(email);

    await _db.collection('users').doc(docId).set({
      'privacyConsentAccepted': true,
      'privacyConsentAcceptedAt': FieldValue.serverTimestamp(),
      'privacyConsentVersion': '1.0',
      'locationAuthorizationAccepted': true,
    }, SetOptions(merge: true));
  }
}
