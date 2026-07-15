import 'package:asistenciapersonal1/models/dashboard_response.dart';
import 'package:asistenciapersonal1/services/api_config.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/dashboard_service.dart';
import 'package:asistenciapersonal1/services/dashboard_refresh_notifier.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardApiService _service;
  late final List<DateTime> _availableMonths;
  late final ScrollController _monthScrollController;
  late DateTime _selectedMonth;
  late Future<DashboardResponse> _future;
  bool _monthSelectorPositioned = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _availableMonths = _buildAvailableMonths(now);
    _monthScrollController = ScrollController();
    _service = DashboardApiService(baseUrl: ApiConfig.baseUrl);
    _future = _load();
    DashboardRefreshNotifier.instance.addListener(_refreshAfterCheckIn);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToCurrentMonth(),
    );
  }

  @override
  void dispose() {
    DashboardRefreshNotifier.instance.removeListener(_refreshAfterCheckIn);
    _monthScrollController.dispose();
    super.dispose();
  }

  Future<DashboardResponse> _load() {
    return _service.getMyDashboard(month: _selectedMonth);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _refreshAfterCheckIn() {
    final now = DateTime.now();
    final isCurrentMonth =
        _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    if (!mounted || !isCurrentMonth) return;

    setState(() {
      _future = _load();
    });
  }

  void _selectMonth(DateTime month) {
    if (_sameMonth(month, _selectedMonth)) return;
    setState(() {
      _selectedMonth = DateTime(month.year, month.month);
      _future = _load();
    });
  }

  void _scrollToCurrentMonth() {
    if (_monthSelectorPositioned || !_monthScrollController.hasClients) return;
    _monthSelectorPositioned = true;
    _monthScrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: const Color(0xFFF4F8FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'SalleTime',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar panel',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A)),
          ),
        ],
      ),
      body: FutureBuilder<DashboardResponse>(
        future: _future,
        builder: (context, snapshot) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
              children: [
                const Text(
                  'Panel de asistencia',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Resumen de tu asistencia mensual',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _MonthSelector(
                  months: _availableMonths,
                  selectedMonth: _selectedMonth,
                  controller: _monthScrollController,
                  onSelected: _selectMonth,
                ),
                const SizedBox(height: 20),
                if (snapshot.connectionState != ConnectionState.done)
                  const _DashboardLoading()
                else if (snapshot.hasError)
                  _DashboardError(error: snapshot.error, onRetry: _refresh)
                else if (snapshot.data == null || !snapshot.data!.hasData)
                  _EmptyDashboard(onRetry: _refresh)
                else
                  _DashboardContent(
                    data: snapshot.data!,
                    onOpenDetail:
                        ({required title, statuses}) => _showAttendanceDetail(
                          snapshot.data!,
                          title: title,
                          statuses: statuses,
                        ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAttendanceDetail(
    DashboardResponse data, {
    required String title,
    Set<String>? statuses,
  }) {
    final daily =
        statuses == null
            ? data.daily
            : data.daily
                .where(
                  (item) => statuses.contains(item.status.trim().toLowerCase()),
                )
                .toList();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF4F8FF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.86,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, controller) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child:
                        daily.isEmpty
                            ? const Center(
                              child: Text(
                                'No hay registros para esta categoría en este periodo.',
                                textAlign: TextAlign.center,
                              ),
                            )
                            : ListView.separated(
                              controller: controller,
                              itemCount: daily.length,
                              separatorBuilder:
                                  (_, _) => const SizedBox(height: 10),
                              itemBuilder:
                                  (_, index) =>
                                      _DailyAttendanceCard(item: daily[index]),
                            ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.data, required this.onOpenDetail});

  final DashboardResponse data;
  final void Function({required String title, Set<String>? statuses})
  onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final summary = data.summary;
    final levelColor = _attendanceLevelColor(summary.attendanceLevel.key);
    final recent = data.recentCheckins.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EmployeePeriodHeader(employee: data.employee, period: data.period),
        const SizedBox(height: 12),
        _PanelCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _CardLabel('ASISTENCIA DEL PERIODO'),
                    const SizedBox(height: 8),
                    Text(
                      '${_formatNumber(summary.compliancePercentage)}%',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StatusPill(
                      label:
                          summary.attendanceLevel.label.isEmpty
                              ? 'Nivel no informado'
                              : summary.attendanceLevel.label,
                      color: levelColor,
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 78,
                    height: 78,
                    child: CircularProgressIndicator(
                      value: (summary.compliancePercentage / 100).clamp(0, 1),
                      strokeWidth: 8,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                    ),
                  ),
                  Icon(Icons.insights_rounded, color: levelColor, size: 26),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () => onOpenDetail(title: 'Detalle de asistencia'),
          borderRadius: BorderRadius.circular(8),
          child: _PanelCard(
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_month_rounded,
                    color: Color(0xFF2563EB),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _CardLabel('DÍAS TRABAJADOS'),
                      const SizedBox(height: 5),
                      Text(
                        summary.workedDaysLabel.isEmpty
                            ? '${summary.workedDays} días trabajados'
                            : summary.workedDaysLabel,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Ver detalle diario',
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'PUNTUALIDAD',
                  value: '${_formatNumber(summary.onTimePercentage)}%',
                  icon: Icons.verified_rounded,
                  color: const Color(0xFF16A34A),
                  onTap:
                      () => onOpenDetail(
                        title: 'Detalle de puntualidad',
                        statuses: const {'puntual'},
                      ),
                  comparison: _comparisonText(
                    summary: data.comparison,
                    value: data.comparison.deltas.onTimePercentage,
                    improved: data.comparison.improved.onTimePercentage,
                    suffix: '%',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: 'TARDANZAS',
                  value: '${summary.lateDays}',
                  icon: Icons.schedule_rounded,
                  color: const Color(0xFFDC2626),
                  onTap:
                      () => onOpenDetail(
                        title: 'Detalle de tardanzas',
                        statuses: const {'tarde'},
                      ),
                  comparison: _comparisonText(
                    summary: data.comparison,
                    value: data.comparison.deltas.lateDays,
                    improved: data.comparison.improved.lateDays,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'SIN MARCA',
                  value: '${summary.missingDays}',
                  icon: Icons.event_busy_rounded,
                  color: const Color(0xFFDC2626),
                  onTap:
                      () => onOpenDetail(
                        title: 'Detalle de días sin marca',
                        statuses: const {'sin_marca'},
                      ),
                  comparison: _comparisonText(
                    summary: data.comparison,
                    value: data.comparison.deltas.missingDays,
                    improved: data.comparison.improved.missingDays,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: 'DÍAS LIBRES',
                  value: '${summary.freeDays}',
                  icon: Icons.beach_access_rounded,
                  color: const Color(0xFF64748B),
                  onTap:
                      () => onOpenDetail(
                        title: 'Detalle de días libres',
                        statuses: const {'dia_libre'},
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _ComparisonCard(comparison: data.comparison),
        const SizedBox(height: 24),
        const Text(
          'Últimas marcaciones',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (recent.isEmpty)
          const _PanelCard(
            child: Text('No hay marcaciones recientes para mostrar.'),
          )
        else
          ...recent.map((item) => _RecentCheckinCard(item: item)),
      ],
    );
  }
}

class _EmployeePeriodHeader extends StatelessWidget {
  const _EmployeePeriodHeader({required this.employee, required this.period});

  final DashboardEmployee employee;
  final DashboardPeriod period;

  @override
  Widget build(BuildContext context) {
    final name = employee.name.trim();
    final code = employee.empCode.trim();
    final periodText =
        period.from.isEmpty || period.to.isEmpty
            ? 'Periodo seleccionado'
            : '${period.from} al ${period.to}';

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7EE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            color: Color(0xFF15803D),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Mi asistencia' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                code.isEmpty ? periodText : 'Código $code · $periodText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.months,
    required this.selectedMonth,
    required this.controller,
    required this.onSelected,
  });

  final List<DateTime> months;
  final DateTime selectedMonth;
  final ScrollController controller;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final month = months[index];
          final selected = _sameMonth(month, selectedMonth);
          return ChoiceChip(
            label: Text(_monthLabel(month)),
            selected: selected,
            onSelected: (_) => onSelected(month),
            avatar:
                selected
                    ? const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 18,
                    )
                    : null,
            showCheckmark: false,
            selectedColor: const Color(0xFFEAF7EE),
            backgroundColor: Colors.white,
            side: BorderSide(
              color:
                  selected ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0),
            ),
            labelStyle: TextStyle(
              color:
                  selected ? const Color(0xFF15803D) : const Color(0xFF475569),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.comparison,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final _ComparisonText? comparison;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = _PanelCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _CardLabel(label)),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 27,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (comparison != null) ...[
            const SizedBox(height: 3),
            Text(
              comparison!.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color:
                    comparison!.improved
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: 'Ver $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.comparison});

  final DashboardComparison comparison;

  @override
  Widget build(BuildContext context) {
    final previous = comparison.previousPeriod;
    if (previous == null) return const SizedBox.shrink();

    final rows = [
      _ComparisonRowData(
        label: 'Cumplimiento',
        icon: Icons.workspace_premium_rounded,
        value: comparison.deltas.compliancePercentage,
        suffix: '%',
        improved: comparison.improved.compliancePercentage,
      ),
      _ComparisonRowData(
        label: 'Puntualidad',
        icon: Icons.verified_rounded,
        value: comparison.deltas.onTimePercentage,
        suffix: '%',
        improved: comparison.improved.onTimePercentage,
      ),
      _ComparisonRowData(
        label: 'Tardanzas',
        icon: Icons.schedule_rounded,
        value: comparison.deltas.lateDays.toDouble(),
        improved: comparison.improved.lateDays,
      ),
      _ComparisonRowData(
        label: 'Sin marca',
        icon: Icons.event_busy_rounded,
        value: comparison.deltas.missingDays.toDouble(),
        improved: comparison.improved.missingDays,
      ),
    ];

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.compare_arrows_rounded,
                  color: Color(0xFF2563EB),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comparación mensual',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Respecto a ${previous.month}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          ...List.generate(
            rows.length,
            (index) => _ComparisonMetricRow(
              row: rows[index],
              showDivider: index < rows.length - 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonMetricRow extends StatelessWidget {
  const _ComparisonMetricRow({required this.row, required this.showDivider});

  final _ComparisonRowData row;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isNeutral = row.value == 0;
    final color =
        isNeutral
            ? const Color(0xFF64748B)
            : row.improved
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);
    final status =
        isNeutral
            ? 'Sin variación'
            : row.improved
            ? 'Mejoró'
            : 'Requiere atención';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(row.icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: TextStyle(color: color, fontSize: 11)),
                  ],
                ),
              ),
              _DeltaBadge(
                value: row.value,
                suffix: row.suffix,
                improved: row.improved,
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(height: 1, color: Color(0xFFE2E8F0)),
      ],
    );
  }
}

class _RecentCheckinCard extends StatelessWidget {
  const _RecentCheckinCard({required this.item});

  final RecentCheckin item;

  @override
  Widget build(BuildContext context) {
    final location =
        item.terminalAlias.isNotEmpty ? item.terminalAlias : item.gpsLocation;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _PanelCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.fingerprint_rounded, color: Color(0xFF2563EB)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.punchDate}  ${item.punchTime}',
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      location,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyAttendanceCard extends StatelessWidget {
  const _DailyAttendanceCard({required this.item});

  final DashboardDaily item;

  @override
  Widget build(BuildContext context) {
    final status = _statusPresentation(item.status);
    final hasSinglePunch =
        item.punchCount <= 1 || item.firstPunch == item.lastPunch;
    final entry = _displayRecordedTime(item.firstPunch);
    final exit = hasSinglePunch ? '-' : _displayRecordedTime(item.lastPunch);
    return _PanelCard(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: status.color, width: 4)),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.date,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusPill(label: status.label, color: status.color),
              ],
            ),
            if (item.schedule.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.schedule,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
            const SizedBox(height: 12),
            _DetailLine(
              label: 'Horario esperado',
              value:
                  '${_displayTime(item.expectedIn)} - ${_displayTime(item.expectedOut)}',
            ),
            _DetailLine(label: 'Entrada registrada', value: entry),
            _DetailLine(label: 'Salida registrada', value: exit),
            _DetailLine(label: 'Cantidad', value: '${item.punchCount}'),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }
}

class _CardLabel extends StatelessWidget {
  const _CardLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _LoadingCard(height: 148),
        SizedBox(height: 12),
        _LoadingCard(height: 90),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _LoadingCard(height: 130)),
            SizedBox(width: 12),
            Expanded(child: _LoadingCard(height: 130)),
          ],
        ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      child: Column(
        children: [
          const Icon(
            Icons.event_note_outlined,
            size: 42,
            color: Color(0xFF64748B),
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay información de asistencia para este periodo',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final appError = error is AppException ? error as AppException : null;
    final dniMissing = appError?.code == 'DASH-403-DNI';
    final message =
        appError?.message ??
        'No pudimos conectar con el servidor de asistencia. Revisa tu conexión e inténtalo nuevamente.';

    return _PanelCard(
      child: Column(
        children: [
          Icon(
            dniMissing ? Icons.badge_outlined : Icons.cloud_off_rounded,
            size: 42,
            color:
                dniMissing ? const Color(0xFFDC2626) : const Color(0xFF64748B),
          ),
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
    );
  }
}

class _ComparisonText {
  const _ComparisonText({required this.text, required this.improved});

  final String text;
  final bool improved;
}

class _ComparisonRowData {
  const _ComparisonRowData({
    required this.label,
    required this.icon,
    required this.value,
    required this.improved,
    this.suffix = '',
  });

  final String label;
  final IconData icon;
  final double value;
  final bool improved;
  final String suffix;
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({
    required this.value,
    required this.suffix,
    required this.improved,
  });

  final double value;
  final String suffix;
  final bool improved;

  @override
  Widget build(BuildContext context) {
    final isNeutral = value == 0;
    final color =
        isNeutral
            ? const Color(0xFF64748B)
            : improved
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);
    final icon =
        isNeutral
            ? Icons.remove_rounded
            : improved
            ? Icons.trending_up_rounded
            : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            '${_signedNumber(value)}$suffix',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPresentation {
  const _StatusPresentation({required this.label, required this.color});

  final String label;
  final Color color;
}

List<DateTime> _buildAvailableMonths(DateTime now) {
  final current = DateTime(now.year, now.month);
  final start = DateTime(now.month >= 3 ? now.year : now.year - 1, 3);
  final months = <DateTime>[];
  var cursor = start;
  while (!cursor.isAfter(current)) {
    months.add(cursor);
    cursor = DateTime(cursor.year, cursor.month + 1);
  }
  return months.reversed.toList();
}

bool _sameMonth(DateTime left, DateTime right) {
  return left.year == right.year && left.month == right.month;
}

String _monthLabel(DateTime date) {
  const labels = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  return labels[date.month - 1];
}

String _formatNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

String _signedNumber(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${_formatNumber(value)}';
}

String _displayTime(String value) => value.isEmpty ? 'Sin marca' : value;

String _displayRecordedTime(String value) => value.isEmpty ? '-' : value;

_ComparisonText? _comparisonText({
  required DashboardComparison summary,
  required num value,
  required bool improved,
  String suffix = '',
}) {
  if (summary.previousPeriod == null) return null;
  return _ComparisonText(
    text: '${_signedNumber(value.toDouble())}$suffix vs. anterior',
    improved: improved,
  );
}

Color _attendanceLevelColor(String level) {
  switch (level.trim().toLowerCase()) {
    case 'destacada':
    case 'excelente':
      return const Color(0xFF16A34A);
    case 'buena':
      return const Color(0xFF2563EB);
    case 'regular':
      return const Color(0xFFD97706);
    case 'baja':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF64748B);
  }
}

_StatusPresentation _statusPresentation(String status) {
  switch (status.trim().toLowerCase()) {
    case 'puntual':
      return const _StatusPresentation(
        label: 'Puntual',
        color: Color(0xFF16A34A),
      );
    case 'tarde':
      return const _StatusPresentation(
        label: 'Tarde',
        color: Color(0xFFDC2626),
      );
    case 'sin_marca':
      return const _StatusPresentation(
        label: 'Sin marca',
        color: Color(0xFFDC2626),
      );
    case 'dia_libre':
      return const _StatusPresentation(
        label: 'Día libre',
        color: Color(0xFF64748B),
      );
    default:
      return _StatusPresentation(
        label: status.isEmpty ? 'No informado' : status,
        color: const Color(0xFF64748B),
      );
  }
}
