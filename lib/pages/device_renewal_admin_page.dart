import 'package:asistenciapersonal1/models/device_renewal.dart';
import 'package:asistenciapersonal1/pages/admin_user_selection_page.dart';
import 'package:asistenciapersonal1/services/api_config.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/device_renewal_service.dart';
import 'package:flutter/material.dart';

class DeviceRenewalAdminPage extends StatefulWidget {
  const DeviceRenewalAdminPage({super.key});

  @override
  State<DeviceRenewalAdminPage> createState() => _DeviceRenewalAdminPageState();
}

class _DeviceRenewalAdminPageState extends State<DeviceRenewalAdminPage> {
  late final DeviceRenewalApiService _service;
  final _reasonController = TextEditingController();
  final _statusEmpCodeController = TextEditingController();

  DateTime _expiresAt = DateTime.now().add(const Duration(days: 7));
  final Set<String> _selectedEmpCodes = <String>{};
  bool _submitting = false;
  bool _consulting = false;
  DeviceRenewalActionResult? _actionResult;
  DeviceRenewalStatus? _status;

  @override
  void initState() {
    super.initState();
    _service = DeviceRenewalApiService(baseUrl: ApiConfig.baseUrl);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _statusEmpCodeController.dispose();
    super.dispose();
  }

  Future<void> _openUserSelector() async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        builder:
            (_) => AdminUserSelectionPage(initialSelection: _selectedEmpCodes),
      ),
    );
    if (selected == null || !mounted) return;

    setState(() {
      _selectedEmpCodes
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _selectExpiration() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Vencimiento de la autorización',
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt),
      helpText: 'Hora de vencimiento',
    );
    if (time == null || !mounted) return;

    setState(() {
      _expiresAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _authorize() async {
    final empCodes = _selectedEmpCodes.toList(growable: false);
    if (empCodes.isEmpty) {
      _showMessage(
        'Selecciona al menos un usuario para autorizar.',
        error: true,
      );
      return;
    }
    if (!_expiresAt.isAfter(DateTime.now())) {
      _showMessage(
        'El vencimiento debe ser posterior a la hora actual.',
        error: true,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final result = await _service.authorize(
        empCodes: empCodes,
        expiresAt: _expiresAt,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      setState(() => _actionResult = result);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _consultStatus() async {
    final codes = parseEmpCodes(_statusEmpCodeController.text);
    if (codes.length != 1) {
      _showMessage('Ingresa un único DNI para consultar.', error: true);
      return;
    }

    setState(() {
      _consulting = true;
      _status = null;
    });
    try {
      final status = await _service.getStatus(codes.single);
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _consulting = false);
    }
  }

  Future<void> _revoke() async {
    final status = _status;
    if (status == null) return;

    setState(() => _submitting = true);
    try {
      final result = await _service.revoke(
        empCodes: [status.empCode],
        reason: _reasonController.text,
      );
      if (!mounted) return;
      setState(() => _actionResult = result);
      await _consultStatus();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message =
        error is AppException
            ? error.userMessage
            : 'No se pudo completar la operación. Inténtalo nuevamente.';
    _showMessage(message, error: true);
  }

  void _showMessage(String message, {required bool error}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            error ? const Color(0xFFB91C1C) : const Color(0xFF166534),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Administrar dispositivos'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _SectionCard(
            title: 'Usuarios a autorizar',
            subtitle:
                'Elige uno, varios o todos los usuarios del directorio de Firestore.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _selectedEmpCodes.isEmpty
                      ? 'Aún no seleccionaste usuarios.'
                      : '${_selectedEmpCodes.length} usuario(s) seleccionado(s).',
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _openUserSelector,
                  icon: const Icon(Icons.group_rounded),
                  label: Text(
                    _selectedEmpCodes.isEmpty
                        ? 'Seleccionar usuarios'
                        : 'Modificar selección',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Autorizar cambio de dispositivo',
            subtitle:
                'Autoriza una sola renovación por usuario hasta el vencimiento indicado.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _selectedEmpCodes.isEmpty
                      ? 'Selecciona usuarios del directorio para continuar.'
                      : '${_selectedEmpCodes.length} usuario(s) seleccionado(s).',
                  style: TextStyle(
                    color:
                        _selectedEmpCodes.isEmpty
                            ? const Color(0xFF64748B)
                            : const Color(0xFF15803D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _selectExpiration,
                  icon: const Icon(Icons.event_available_rounded),
                  label: Text('Vence: ${formatDateTime(_expiresAt)}'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _reasonController,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                    hintText: 'Actualización de aplicación',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _submitting ? null : _authorize,
                  icon:
                      _submitting
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Icon(Icons.verified_user_rounded),
                  label: Text(
                    _submitting
                        ? 'Actualizando autorización...'
                        : 'Autorizar cambio de dispositivo',
                  ),
                ),
              ],
            ),
          ),
          if (_actionResult != null) ...[
            const SizedBox(height: 16),
            _ActionResultsCard(result: _actionResult!),
          ],
          const SizedBox(height: 22),
          _SectionCard(
            title: 'Consultar autorización',
            subtitle:
                'Consulta el estado actual de un usuario antes de revocar una autorización.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _statusEmpCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'DNI',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _consultStatus(),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _consulting ? null : _consultStatus,
                  icon:
                      _consulting
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.search_rounded),
                  label: Text(_consulting ? 'Consultando...' : 'Consultar'),
                ),
              ],
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            _StatusCard(status: _status!, busy: _submitting, onRevoke: _revoke),
          ],
        ],
      ),
    );
  }
}

List<String> parseEmpCodes(String value) {
  final unique = <String>{};
  for (final item in value.split(RegExp(r'[,;\s]+'))) {
    final code = item.trim();
    if (code.isNotEmpty) unique.add(code);
  }
  return unique.toList(growable: false);
}

String formatDateTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ActionResultsCard extends StatelessWidget {
  const _ActionResultsCard({required this.result});

  final DeviceRenewalActionResult result;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Resultado de la operación',
      subtitle: 'El backend valida cada DNI de forma independiente.',
      child: Column(
        children: [
          ...result.authorized.map(
            (item) => _ResultRow(
              empCode: item.empCode,
              message:
                  result.isRevocation
                      ? 'Autorización revocada'
                      : item.email.isEmpty
                      ? 'Cambio de dispositivo autorizado'
                      : 'Cambio de dispositivo autorizado para ${item.email}',
              color: const Color(0xFF15803D),
              icon: Icons.check_circle_rounded,
            ),
          ),
          ...result.failed.map(
            (item) => _ResultRow(
              empCode: item.empCode,
              message:
                  item.detail.isEmpty
                      ? 'No se pudo completar la operación'
                      : item.detail,
              color: const Color(0xFFB91C1C),
              icon: Icons.error_rounded,
            ),
          ),
          if (result.authorized.isEmpty && result.failed.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('La API no devolvió resultados por usuario.'),
            ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.empCode,
    required this.message,
    required this.color,
    required this.icon,
  });

  final String empCode;
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: Color(0xFF334155)),
                children: [
                  TextSpan(
                    text: empCode.isEmpty ? 'Usuario' : empCode,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: ': $message'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.busy,
    required this.onRevoke,
  });

  final DeviceRenewalStatus status;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final replacement = status.deviceReplacement;
    final active = replacement?.allowed == true && replacement?.usedAt == null;
    final color = active ? const Color(0xFF15803D) : const Color(0xFF64748B);

    return _SectionCard(
      title: 'Estado de ${status.empCode}',
      subtitle: status.email.isEmpty ? 'Sin correo informado' : status.email,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                active ? 'Autorización vigente' : 'Sin autorización vigente',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (replacement != null) ...[
            if (replacement.expiresAt != null) ...[
              const SizedBox(height: 10),
              Text(
                'Vence: ${formatDateTime(replacement.expiresAt!.toLocal())}',
              ),
            ],
            if (replacement.usedAt != null) ...[
              const SizedBox(height: 6),
              Text(
                'Utilizada: ${formatDateTime(replacement.usedAt!.toLocal())}',
              ),
            ],
            if (replacement.reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Motivo: ${replacement.reason}'),
            ],
          ],
          if (active) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : onRevoke,
              icon: const Icon(Icons.block_rounded),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
              ),
              label: const Text('Revocar autorización'),
            ),
          ],
        ],
      ),
    );
  }
}
