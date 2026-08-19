import 'package:asistenciapersonal1/models/admin_directory_user.dart';
import 'package:asistenciapersonal1/services/admin_user_directory_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminUserSelectionPage extends StatefulWidget {
  const AdminUserSelectionPage({super.key, required this.initialSelection});

  final Set<String> initialSelection;

  @override
  State<AdminUserSelectionPage> createState() => _AdminUserSelectionPageState();
}

class _AdminUserSelectionPageState extends State<AdminUserSelectionPage> {
  final _service = AdminUserDirectoryService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _users = <AdminDirectoryUser>[];
  late final Set<String> _selectedEmpCodes;

  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _hasMore = true;
  bool _loading = false;
  bool _selectingAll = false;
  bool _allDirectorySelected = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedEmpCodes = {...widget.initialSelection};
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 320) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final page = await _service.getUsers(startAfter: _lastDocument);
      if (!mounted) return;
      setState(() {
        _users.addAll(page.users);
        _lastDocument = page.lastDocument;
        _hasMore = page.hasMore;
      });
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            error.code == 'permission-denied'
                ? 'No tienes permisos de Firestore para consultar el directorio.'
                : 'No se pudo cargar el directorio de usuarios.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'No se pudo cargar el directorio de usuarios.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAllDirectoryUsers() async {
    if (_selectingAll) return;
    if (_allDirectorySelected) {
      setState(() {
        _selectedEmpCodes.clear();
        _allDirectorySelected = false;
      });
      return;
    }

    setState(() => _selectingAll = true);
    try {
      while (_hasMore) {
        await _loadNextPage();
        if (!mounted || _errorMessage != null) return;
      }
      if (!mounted) return;
      setState(() {
        _selectedEmpCodes.addAll(
          _users.where((user) => user.hasDni).map((user) => user.dni),
        );
        _allDirectorySelected = true;
      });
    } finally {
      if (mounted) setState(() => _selectingAll = false);
    }
  }

  void _toggleUser(AdminDirectoryUser user, bool selected) {
    if (!user.hasDni) return;
    setState(() {
      if (selected) {
        _selectedEmpCodes.add(user.dni);
      } else {
        _selectedEmpCodes.remove(user.dni);
        _allDirectorySelected = false;
      }
    });
  }

  List<AdminDirectoryUser> get _visibleUsers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users
        .where(
          (user) =>
              user.dni.toLowerCase().contains(query) ||
              user.name.toLowerCase().contains(query) ||
              user.email.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visibleUsers = _visibleUsers;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Seleccionar usuarios'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed:
                _loading || _selectingAll ? null : _toggleAllDirectoryUsers,
            child:
                _selectingAll
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(_allDirectorySelected ? 'Quitar todos' : 'Todos'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Buscar por nombre, DNI o correo',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon:
                        _searchController.text.isEmpty
                            ? null
                            : IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear_rounded),
                            ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_selectedEmpCodes.length} seleccionados · '
                    '${_users.length} cargados',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                _errorMessage != null && _users.isEmpty
                    ? _ErrorState(
                      message: _errorMessage!,
                      onRetry: _loadNextPage,
                    )
                    : visibleUsers.isEmpty && !_loading
                    ? const Center(
                      child: Text(
                        'No se encontraron usuarios en el directorio.',
                      ),
                    )
                    : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 96),
                      itemCount: visibleUsers.length + (_loading ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index == visibleUsers.length) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final user = visibleUsers[index];
                        return Material(
                          color: Colors.white,
                          child: CheckboxListTile(
                            value: _selectedEmpCodes.contains(user.dni),
                            onChanged:
                                user.hasDni
                                    ? (selected) =>
                                        _toggleUser(user, selected ?? false)
                                    : null,
                            controlAffinity: ListTileControlAffinity.trailing,
                            title: Text(
                              user.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              user.hasDni
                                  ? '${user.dni} · ${user.email}'
                                  : 'Sin DNI registrado · ${user.email}',
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_selectedEmpCodes),
          icon: const Icon(Icons.check_rounded),
          label: Text('Usar ${_selectedEmpCodes.length} usuario(s)'),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
