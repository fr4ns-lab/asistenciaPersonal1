// ignore_for_file: public_member_api_docs, avoid_print

import 'dart:async';
import 'dart:convert' show json;

import 'package:flutter/material.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;

const List<String> _scopes = <String>[
  'https://www.googleapis.com/auth/userinfo.email',
  'https://www.googleapis.com/auth/userinfo.profile',
  // Si NO necesitas contactos, puedes quitarlo:
  'https://www.googleapis.com/auth/contacts.readonly',
];

class SignInDemo extends StatefulWidget {
  const SignInDemo({super.key});

  @override
  State createState() => SignInDemoState();
}

class SignInDemoState extends State<SignInDemo> {
  GoogleSignInUserData? _currentUser;
  String? _photoUrlFinal;

  bool _isAuthorized = false;
  String _status = '';
  String _errorMessage = '';
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    unawaited(_handleSignIn());
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= GoogleSignInPlatform.instance.init(
      const InitParameters(),
    )..catchError((dynamic _) {
      _initialization = null;
    });
  }

  // 1) Asegura tokens + scopes (IMPORTANTE: promptIfUnauthorized true)
  Future<ClientAuthorizationTokenData?> _ensureTokens(
    GoogleSignInUserData user,
  ) async {
    final tokens = await GoogleSignInPlatform.instance
        .clientAuthorizationTokensForScopes(
          ClientAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(
              scopes: _scopes,
              userId: user.id,
              email: user.email,
              promptIfUnauthorized: true, // <-- CLAVE
            ),
          ),
        );
    return tokens;
  }

  Future<Map<String, String>?> _authHeaders(GoogleSignInUserData user) async {
    final tokens = await _ensureTokens(user);
    if (tokens == null) return null;

    return <String, String>{
      'Authorization': 'Bearer ${tokens.accessToken}',
      'X-Goog-AuthUser': '0',
    };
  }

  // 2) Fallback #1: endpoint userinfo (suele devolver "picture")
  Future<String?> _fetchPhotoFromUserInfo(GoogleSignInUserData user) async {
    final headers = await _authHeaders(user);
    if (headers == null) return null;

    final res = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      headers: headers,
    );

    debugPrint('userinfo status: ${res.statusCode}');
    debugPrint('userinfo body: ${res.body}');

    if (res.statusCode != 200) return null;

    final data = json.decode(res.body) as Map<String, dynamic>;
    return data['picture'] as String?;
  }

  // 3) Fallback #2: People API (people/me -> photos)
  Future<String?> _fetchPhotoFromPeopleApi(GoogleSignInUserData user) async {
    final headers = await _authHeaders(user);
    if (headers == null) return null;

    final res = await http.get(
      Uri.parse(
        'https://people.googleapis.com/v1/people/me?personFields=photos',
      ),
      headers: headers,
    );

    debugPrint('people/me status: ${res.statusCode}');
    debugPrint('people/me body: ${res.body}');

    if (res.statusCode != 200) return null;

    final data = json.decode(res.body) as Map<String, dynamic>;
    final photos = (data['photos'] as List?) ?? [];
    if (photos.isEmpty) return null;

    return photos.first['url'] as String?;
  }

  Future<void> _postLogin(GoogleSignInUserData user) async {
    setState(() {
      _status = 'Buscando foto...';
      _errorMessage = '';
    });

    debugPrint('SDK photoUrl: ${user.photoUrl}');

    // a) Primero: lo que da el SDK
    String? url = user.photoUrl;

    // b) Si no hay, prueba userinfo (picture)
    url ??= await _fetchPhotoFromUserInfo(user);

    // c) Si no hay, prueba People API
    url ??= await _fetchPhotoFromPeopleApi(user);

    debugPrint('FINAL photoUrl: $url');

    if (!mounted) return;
    setState(() {
      _photoUrlFinal = url;
      _status =
          url == null ? 'Sin foto (o bloqueado por política).' : 'Foto OK';
      _isAuthorized = true;
    });
  }

  Future<void> _handleSignIn() async {
    try {
      await _ensureInitialized();

      // Renovar tokens para que agarre permisos nuevos del Admin
      await GoogleSignInPlatform.instance.disconnect(const DisconnectParams());

      final AuthenticationResults result = await GoogleSignInPlatform.instance
          .authenticate(const AuthenticateParameters());

      setState(() {
        _currentUser = result.user;
      });

      if (result.user != null) {
        await _postLogin(result.user!);
      }
    } on GoogleSignInException catch (e) {
      setState(() {
        _errorMessage =
            e.code == GoogleSignInExceptionCode.canceled
                ? ''
                : 'GoogleSignInException ${e.code}: ${e.description}';
      });
    }
  }

  Future<void> _handleSignOut() async {
    await _ensureInitialized();
    await GoogleSignInPlatform.instance.disconnect(const DisconnectParams());
    if (!mounted) return;
    setState(() {
      _currentUser = null;
      _photoUrlFinal = null;
      _isAuthorized = false;
      _status = '';
      _errorMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Google Sign In')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (user == null) ...[
                const Text('No has iniciado sesión.'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _handleSignIn,
                  child: const Text('SIGN IN'),
                ),
              ] else ...[
                ListTile(
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundImage:
                        (_photoUrlFinal != null && _photoUrlFinal!.isNotEmpty)
                            ? NetworkImage(_photoUrlFinal!)
                            : null,
                    child:
                        (_photoUrlFinal == null || _photoUrlFinal!.isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                  ),
                  title: Text(user.displayName ?? ''),
                  subtitle: Text(user.email),
                ),
                const SizedBox(height: 8),
                Text('Estado: $_status'),
                Text('SDK photoUrl: ${user.photoUrl}'),
                Text('Final photoUrl: $_photoUrlFinal'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _handleSignOut,
                  child: const Text('SIGN OUT'),
                ),
              ],
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_errorMessage),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
