/// Currency, date and status formatting helpers (en-IN style).
library formatters;

String inr(num? value) {
  final amount = (value ?? 0).toDouble();
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  var digits = parts[0];
  var out = '';
  if (digits.length > 3) {
    out = digits.substring(digits.length - 3);
    digits = digits.substring(0, digits.length - 3);
    while (digits.length > 2) {
      out = '${digits.substring(digits.length - 2)},$out';
      digits = digits.substring(0, digits.length - 2);
    }
    if (digits.isNotEmpty) out = '$digits,$out';
  } else {
    out = digits;
  }
  final paisa = parts[1];
  final suffix = paisa == '00' ? '' : '.$paisa';
  return '${negative ? '-' : ''}₹$out$suffix';
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDate(String? value) {
  if (value == null || value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final day = parsed.day.toString().padLeft(2, '0');
  return '$day ${_months[parsed.month - 1]} ${parsed.year}';
}

String formatDateShort(String? value) {
  if (value == null || value.isEmpty) return '—';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final day = parsed.day.toString().padLeft(2, '0');
  return '$day ${_months[parsed.month - 1]}';
}

String todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}

String monthIso(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

String timeLabel(String? value) {
  if (value == null || value.isEmpty) return '—';
  final parts = value.split(':');
  if (parts.length != 2) return value;
  final hour = int.tryParse(parts[0]);
  final minute = parts[1];
  if (hour == null) return value;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final twelve = hour % 12 == 0 ? 12 : hour % 12;
  return '$twelve:$minute $suffix';
}

String statusColorName(String status) {
  switch (status) {
    case 'Confirmed':
    case 'Active':
    case 'Paid':
    case 'Available':
      return 'green';
    case 'Pending':
    case 'Maintenance':
      return 'amber';
    case 'Cancelled':
    case 'Inactive':
      return 'red';
    case 'Completed':
      return 'blue';
    default:
      return 'grey';
  }
}

String pluralCount(int count, String singular, {String? plural}) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
