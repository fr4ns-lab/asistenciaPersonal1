class DashboardResponse {
  const DashboardResponse({
    required this.employee,
    required this.period,
    required this.evaluationPeriod,
    required this.summary,
    required this.comparison,
    required this.statusCounts,
    required this.daily,
    required this.recentCheckins,
  });

  final DashboardEmployee employee;
  final DashboardPeriod period;
  final DashboardEvaluationPeriod evaluationPeriod;
  final DashboardSummary summary;
  final DashboardComparison comparison;
  final Map<String, int> statusCounts;
  final List<DashboardDaily> daily;
  final List<RecentCheckin> recentCheckins;

  factory DashboardResponse.fromJson(Map<String, dynamic> json) {
    return DashboardResponse(
      employee: DashboardEmployee.fromJson(_map(json['employee'])),
      period: DashboardPeriod.fromJson(_map(json['period'])),
      evaluationPeriod: DashboardEvaluationPeriod.fromJson(
        _map(json['evaluation_period']),
      ),
      summary: DashboardSummary.fromJson(_map(json['summary'])),
      comparison: DashboardComparison.fromJson(_map(json['comparison'])),
      statusCounts: _intMap(json['status_counts']),
      daily: _list(json['daily']).map(DashboardDaily.fromJson).toList(),
      recentCheckins:
          _list(json['recent_checkins']).map(RecentCheckin.fromJson).toList(),
    );
  }

  bool get hasData {
    return summary.expectedWorkingDays > 0 ||
        summary.monthExpectedWorkingDays > 0 ||
        summary.workedDays > 0 ||
        summary.freeDays > 0 ||
        daily.isNotEmpty ||
        recentCheckins.isNotEmpty;
  }
}

class DashboardEmployee {
  const DashboardEmployee({
    required this.empCode,
    required this.name,
    required this.email,
  });

  final String empCode;
  final String name;
  final String email;

  factory DashboardEmployee.fromJson(Map<String, dynamic> json) {
    return DashboardEmployee(
      empCode: _string(json['emp_code']),
      name: _string(json['name']),
      email: _string(json['email']),
    );
  }
}

class DashboardPeriod {
  const DashboardPeriod({required this.from, required this.to});

  final String from;
  final String to;

  factory DashboardPeriod.fromJson(Map<String, dynamic> json) {
    return DashboardPeriod(
      from: _string(json['from']),
      to: _string(json['to']),
    );
  }
}

class DashboardEvaluationPeriod {
  const DashboardEvaluationPeriod({
    required this.from,
    required this.to,
    required this.isComplete,
  });

  final String from;
  final String to;
  final bool isComplete;

  factory DashboardEvaluationPeriod.fromJson(Map<String, dynamic> json) {
    return DashboardEvaluationPeriod(
      from: _string(json['from']),
      to: _string(json['to']),
      isComplete: _bool(json['is_complete']),
    );
  }
}

class AttendanceLevel {
  const AttendanceLevel({required this.key, required this.label});

  final String key;
  final String label;

  factory AttendanceLevel.fromJson(Map<String, dynamic> json) {
    return AttendanceLevel(
      key: _string(json['key']),
      label: _string(json['label']),
    );
  }
}

class DashboardSummary {
  const DashboardSummary({
    required this.expectedWorkingDays,
    required this.workedDays,
    required this.completeMarkDays,
    required this.incompleteMarkDays,
    required this.monthExpectedWorkingDays,
    required this.remainingScheduledDays,
    required this.evaluatedThrough,
    required this.onTimeDays,
    required this.lateDays,
    required this.lateMinutesTotal,
    required this.lateMinutesLabel,
    required this.earlyDepartureDays,
    required this.earlyDepartureMinutesTotal,
    required this.earlyDepartureMinutesLabel,
    required this.scheduleIncidenceMinutesTotal,
    required this.scheduleIncidenceMinutesLabel,
    required this.missingDays,
    required this.freeDays,
    required this.onTimePercentage,
    required this.compliancePercentage,
    required this.attendanceLevel,
    required this.workedDaysLabel,
    required this.missingDaysLabel,
  });

  final int expectedWorkingDays;
  final int workedDays;
  final int completeMarkDays;
  final int incompleteMarkDays;
  final int monthExpectedWorkingDays;
  final int remainingScheduledDays;
  final String evaluatedThrough;
  final int onTimeDays;
  final int lateDays;
  final int lateMinutesTotal;
  final String lateMinutesLabel;
  final int earlyDepartureDays;
  final int earlyDepartureMinutesTotal;
  final String earlyDepartureMinutesLabel;
  final int scheduleIncidenceMinutesTotal;
  final String scheduleIncidenceMinutesLabel;
  final int missingDays;
  final int freeDays;
  final double onTimePercentage;
  final double compliancePercentage;
  final AttendanceLevel attendanceLevel;
  final String workedDaysLabel;
  final String missingDaysLabel;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      expectedWorkingDays: _int(json['expected_working_days']),
      workedDays: _int(json['worked_days']),
      completeMarkDays: _int(json['complete_mark_days']),
      incompleteMarkDays: _int(json['incomplete_mark_days']),
      monthExpectedWorkingDays: _int(json['month_expected_working_days']),
      remainingScheduledDays: _int(json['remaining_scheduled_days']),
      evaluatedThrough: _string(json['evaluated_through']),
      onTimeDays: _int(json['on_time_days']),
      lateDays: _int(json['late_days']),
      lateMinutesTotal: _int(json['late_minutes_total']),
      lateMinutesLabel: _string(json['late_minutes_label']),
      earlyDepartureDays: _int(json['early_departure_days']),
      earlyDepartureMinutesTotal: _int(json['early_departure_minutes_total']),
      earlyDepartureMinutesLabel: _string(
        json['early_departure_minutes_label'],
      ),
      scheduleIncidenceMinutesTotal: _int(
        json['schedule_incidence_minutes_total'],
      ),
      scheduleIncidenceMinutesLabel: _string(
        json['schedule_incidence_minutes_label'],
      ),
      missingDays: _int(json['missing_days']),
      freeDays: _int(json['free_days']),
      onTimePercentage: _double(json['on_time_percentage']),
      compliancePercentage: _double(json['compliance_percentage']),
      attendanceLevel: AttendanceLevel.fromJson(_map(json['attendance_level'])),
      workedDaysLabel: _string(json['worked_days_label']),
      missingDaysLabel: _string(json['missing_days_label']),
    );
  }
}

class DashboardComparison {
  const DashboardComparison({
    required this.previousPeriod,
    required this.previousSummary,
    required this.deltas,
    required this.improved,
  });

  final DashboardPreviousPeriod? previousPeriod;
  final DashboardSummary? previousSummary;
  final DashboardDeltas deltas;
  final DashboardImprovements improved;

  factory DashboardComparison.fromJson(Map<String, dynamic> json) {
    final previousPeriod = _map(json['previous_period']);
    final previousSummary = _map(json['previous_summary']);
    return DashboardComparison(
      previousPeriod:
          previousPeriod.isEmpty
              ? null
              : DashboardPreviousPeriod.fromJson(previousPeriod),
      previousSummary:
          previousSummary.isEmpty
              ? null
              : DashboardSummary.fromJson(previousSummary),
      deltas: DashboardDeltas.fromJson(_map(json['deltas'])),
      improved: DashboardImprovements.fromJson(_map(json['improved'])),
    );
  }
}

class DashboardPreviousPeriod {
  const DashboardPreviousPeriod({
    required this.from,
    required this.to,
    required this.month,
  });

  final String from;
  final String to;
  final String month;

  factory DashboardPreviousPeriod.fromJson(Map<String, dynamic> json) {
    return DashboardPreviousPeriod(
      from: _string(json['from']),
      to: _string(json['to']),
      month: _string(json['month']),
    );
  }
}

class DashboardDeltas {
  const DashboardDeltas({
    required this.workedDays,
    required this.onTimeDays,
    required this.lateDays,
    required this.missingDays,
    required this.onTimePercentage,
    required this.compliancePercentage,
  });

  final int workedDays;
  final int onTimeDays;
  final int lateDays;
  final int missingDays;
  final double onTimePercentage;
  final double compliancePercentage;

  factory DashboardDeltas.fromJson(Map<String, dynamic> json) {
    return DashboardDeltas(
      workedDays: _int(json['worked_days']),
      onTimeDays: _int(json['on_time_days']),
      lateDays: _int(json['late_days']),
      missingDays: _int(json['missing_days']),
      onTimePercentage: _double(json['on_time_percentage']),
      compliancePercentage: _double(json['compliance_percentage']),
    );
  }
}

class DashboardImprovements {
  const DashboardImprovements({
    required this.lateDays,
    required this.missingDays,
    required this.onTimePercentage,
    required this.compliancePercentage,
  });

  final bool lateDays;
  final bool missingDays;
  final bool onTimePercentage;
  final bool compliancePercentage;

  factory DashboardImprovements.fromJson(Map<String, dynamic> json) {
    return DashboardImprovements(
      lateDays: _bool(json['late_days']),
      missingDays: _bool(json['missing_days']),
      onTimePercentage: _bool(json['on_time_percentage']),
      compliancePercentage: _bool(json['compliance_percentage']),
    );
  }
}

class DashboardDaily {
  const DashboardDaily({
    required this.date,
    required this.schedule,
    required this.expectedIn,
    required this.expectedOut,
    required this.firstPunch,
    required this.lastPunch,
    required this.punchCount,
    required this.markStatus,
    required this.status,
    required this.singleMarkAssumption,
    required this.lateMinutes,
    required this.lateArrivalMinutes,
    required this.earlyDepartureMinutes,
    required this.scheduleIncidenceMinutes,
  });

  final String date;
  final String schedule;
  final String expectedIn;
  final String expectedOut;
  final String firstPunch;
  final String lastPunch;
  final int punchCount;
  final String markStatus;
  final String status;
  final String? singleMarkAssumption;
  final int lateMinutes;
  final int lateArrivalMinutes;
  final int earlyDepartureMinutes;
  final int scheduleIncidenceMinutes;

  factory DashboardDaily.fromJson(Map<String, dynamic> json) {
    return DashboardDaily(
      date: _string(json['date']),
      schedule: _string(json['schedule']),
      expectedIn: _string(json['expected_in']),
      expectedOut: _string(json['expected_out']),
      firstPunch: _string(json['first_punch']),
      lastPunch: _string(json['last_punch']),
      punchCount: _int(json['punch_count']),
      markStatus: _string(json['mark_status']),
      status: _string(json['status']),
      singleMarkAssumption: _nullableString(json['single_mark_assumption']),
      lateMinutes: _int(json['late_minutes']),
      lateArrivalMinutes: _int(json['late_arrival_minutes']),
      earlyDepartureMinutes: _int(json['early_departure_minutes']),
      scheduleIncidenceMinutes: _int(json['schedule_incidence_minutes']),
    );
  }
}

class RecentCheckin {
  const RecentCheckin({
    required this.id,
    required this.punchDate,
    required this.punchTime,
    required this.punchState,
    required this.terminalAlias,
    required this.gpsLocation,
    required this.latitude,
    required this.longitude,
  });

  final int id;
  final String punchDate;
  final String punchTime;
  final String punchState;
  final String terminalAlias;
  final String gpsLocation;
  final double? latitude;
  final double? longitude;

  factory RecentCheckin.fromJson(Map<String, dynamic> json) {
    return RecentCheckin(
      id: _int(json['id']),
      punchDate: _string(json['punch_date']),
      punchTime: _string(json['punch_time']),
      punchState: _string(json['punch_state']),
      terminalAlias: _string(json['terminal_alias']),
      gpsLocation: _string(json['gps_location']),
      latitude: _nullableDouble(json['latitude']),
      longitude: _nullableDouble(json['longitude']),
    );
  }
}

typedef RecentCheckIn = RecentCheckin;

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.map(_map).where((item) => item.isNotEmpty).toList();
}

Map<String, int> _intMap(Object? value) {
  return _map(value).map((key, item) => MapEntry(key, _int(item)));
}

String _string(Object? value) => value?.toString() ?? '';

String? _nullableString(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

bool _bool(Object? value) => value is bool ? value : value == true;

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
