class LimaTime {
  LimaTime._();

  static const utcOffset = Duration(hours: -5);

  /// Produces Lima wall time from an instant, independently of device timezone.
  static DateTime fromInstant(DateTime dateTime) {
    return dateTime.toUtc().add(utcOffset);
  }

  static DateTime now() => fromInstant(DateTime.now());

  /// API timestamps without an explicit offset are treated as UTC by contract.
  static DateTime parseApiTimestamp(String value) {
    final parsed = DateTime.parse(value);
    final utc =
        parsed.isUtc
            ? parsed
            : DateTime.utc(
              parsed.year,
              parsed.month,
              parsed.day,
              parsed.hour,
              parsed.minute,
              parsed.second,
              parsed.millisecond,
              parsed.microsecond,
            );
    return fromInstant(utc);
  }
}
