/// Port of `shared/booking-duration.js` — duration windows and overlap checks.
///
/// All instants are UTC to match the server's `T…Z` parsing exactly.
library duration;

class DurationOption {
  const DurationOption(this.value, this.label, this.hint, {this.start, this.end});
  final String value;
  final String label;
  final String hint;
  final String? start;
  final String? end;
}

const List<DurationOption> durationOptions = <DurationOption>[
  DurationOption('full', 'Full day', '00:00–24:00', start: '00:00', end: '00:00'),
  DurationOption('morning', 'Morning', '08:00–14:00', start: '08:00', end: '14:00'),
  DurationOption('afternoon', 'Afternoon', '14:00–20:00', start: '14:00', end: '20:00'),
  DurationOption('evening', 'Evening', '17:00–23:00', start: '17:00', end: '23:00'),
  DurationOption('multiple', 'Multiple days', 'Full days, inclusive'),
  DurationOption('custom', 'Custom timing', 'Choose start and end'),
];

final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final RegExp _timePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

bool validDate(String? value) {
  if (value == null || !_datePattern.hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  // Reject rolled-over dates such as 2026-02-30 by re-formatting the parsed
  // calendar components and comparing against the input.
  final asDay = DateTime.utc(parsed.year, parsed.month, parsed.day);
  return asDay.year == parsed.year &&
      asDay.month == parsed.month &&
      asDay.day == parsed.day &&
      asDay.toIso8601String().substring(0, 10) == value;
}

String nextDate(String date) {
  final parsed = DateTime.parse(date).toUtc();
  final next = DateTime.utc(parsed.year, parsed.month, parsed.day)
      .add(const Duration(days: 1));
  return next.toIso8601String().substring(0, 10);
}

class BookingWindow {
  BookingWindow({
    required this.mode,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.start,
    required this.end,
    required this.days,
    required this.rentalUnits,
    required this.rateKey,
  });

  final String mode;
  final String label;
  final String startDate;
  final String endDate;
  final String startTime;
  final String endTime;
  final DateTime start;
  final DateTime end;
  final int days;
  final int rentalUnits;
  final String rateKey;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'mode': mode,
        'label': label,
        'startDate': startDate,
        'endDate': endDate,
        'startTime': startTime,
        'endTime': endTime,
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'days': days,
        'rentalUnits': rentalUnits,
        'rateKey': rateKey,
      };
}

const int _dayMs = 86400000;

/// Mirrors the server-side `bookingDuration()` contract.
BookingWindow bookingDuration(Map<String, dynamic> input) {
  final date = input['date'] as String?;
  if (!validDate(date)) {
    throw ApiExceptionLike('Choose a valid event date.');
  }
  final mode = (input['durationMode'] as String?) ?? 'full';
  DurationOption? option;
  for (final candidate in durationOptions) {
    if (candidate.value == mode) option = candidate;
  }
  if (option == null) throw ApiExceptionLike('Choose a valid booking duration.');
  final endDateInput =
      (mode == 'multiple' || mode == 'custom') ? (input['endDate'] as String? ?? date) : date;
  if (!validDate(endDateInput) || endDateInput!.compareTo(date!) < 0) {
    throw ApiExceptionLike('End date must be on or after the start date.');
  }
  var startTime = option.start ?? '00:00';
  var endTime = option.end ?? '00:00';
  if (mode == 'custom') {
    startTime = (input['time'] as String?) ?? '';
    endTime = (input['bookingEndTime'] as String?) ?? '';
    if (!_timePattern.hasMatch(startTime) || !_timePattern.hasMatch(endTime)) {
      throw ApiExceptionLike('Enter a valid booking start and end time.');
    }
  }
  final effectiveEndDay =
      (mode == 'full' || mode == 'multiple') ? nextDate(endDateInput) : endDateInput;
  final start = DateTime.parse('${date}T$startTime:00Z').toUtc();
  final end = DateTime.parse('${effectiveEndDay}T$endTime:00Z').toUtc();
  if (!end.isAfter(start)) {
    throw ApiExceptionLike(
        'Booking end must be after its start. For overnight events, choose the next end date.');
  }
  if (end.difference(start).inMilliseconds > 31 * _dayMs) {
    throw ApiExceptionLike('A booking may reserve up to 31 days.');
  }
  final dayStart = DateTime.parse('${date}T00:00:00Z').toUtc();
  int days;
  if (mode == 'custom') {
    days = (end.difference(dayStart).inMilliseconds / _dayMs).ceil();
  } else if (mode == 'multiple') {
    days = (end.difference(start).inMilliseconds / _dayMs).round();
  } else {
    days = 1;
  }
  final rateKey = (mode == 'morning' || mode == 'afternoon' || mode == 'evening')
      ? '${mode}Price'
      : 'price';
  return BookingWindow(
    mode: mode,
    label: option.label,
    startDate: date,
    endDate: effectiveEndDay,
    startTime: startTime,
    endTime: endTime,
    start: start,
    end: end,
    days: days,
    rentalUnits: days,
    rateKey: rateKey,
  );
}

bool bookingsOverlap(Map<String, dynamic> a, Map<String, dynamic> b) {
  final x = bookingDuration(a);
  final y = bookingDuration(b);
  return x.start.isBefore(y.end) && y.start.isBefore(x.end);
}

/// True when [booking] occupies [date] (used by the calendar screen).
bool occupiesDate(Map<String, dynamic> booking, String date) {
  try {
    return bookingsOverlap(booking, <String, dynamic>{'date': date});
  } catch (_) {
    return booking['date'] == date;
  }
}

String durationDescription(Map<String, dynamic> input) {
  try {
    final d = bookingDuration(input);
    final extra = d.days > 1 ? ' · ${d.days} rental days' : '';
    return '${d.label} · ${d.startDate} ${d.startTime} → ${d.endDate} ${d.endTime}$extra';
  } catch (e) {
    return e is ApiExceptionLike ? e.message : 'Choose a valid booking duration';
  }
}

/// Lightweight error type shared by the pure calculation ports.
class ApiExceptionLike implements Exception {
  ApiExceptionLike(this.message);
  final String message;
  @override
  String toString() => message;
}
