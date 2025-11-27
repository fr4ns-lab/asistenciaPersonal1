class TransactionRequest {
  final String empCode;
  final String? punchTime; // lo mandamos como ISO8601 con zona
  final int punchState;
  final int verifyType;
  final int? workCode;
  final String terminalSn;
  final String? terminalAlias;
  final String? areaAlias;
  final double? longitude;
  final double? latitude;
  final String? gpsLocation;
  final bool? mobile;
  final int source;
  final int? purpose;
  final String? crc;
  final int isAttendance;
  final String? reserved;
  final int syncStatus;
  final String? syncTime;
  final int isMask;
  final double temperature;

  TransactionRequest({
    required this.empCode,
    required this.punchTime,
    this.punchState = 0,
    this.verifyType = 0,
    this.workCode,
    this.terminalSn = 'App',
    this.terminalAlias,
    this.areaAlias,
    this.longitude,
    this.latitude,
    this.gpsLocation,
    this.mobile,
    this.source = 3,
    this.purpose = 1,
    this.crc,
    this.isAttendance = 1,
    this.reserved,
    this.syncStatus = 0,
    this.syncTime,
    this.isMask = 255,
    this.temperature = 255.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'emp_code': empCode,
      'punch_time': punchTime,
      'punch_state': punchState,
      'verify_type': verifyType,
      'work_code': workCode,
      'terminal_sn': terminalSn,
      'terminal_alias': terminalAlias,
      'area_alias': areaAlias,
      'longitude': longitude,
      'latitude': latitude,
      'gps_location': gpsLocation,
      'mobile': mobile,
      'source': source,
      'purpose': purpose,
      'crc': crc,
      'is_attendance': isAttendance,
      'reserved': reserved,
      'sync_status': syncStatus,
      'sync_time': syncTime,
      'is_mask': isMask,
      'temperature': temperature,
    };
  }
}
