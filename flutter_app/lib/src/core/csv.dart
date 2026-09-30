/// Minimal RFC 4180 CSV encoder for exports.
String csvEncode(List<List<String>> rows) {
  final buffer = StringBuffer();
  for (final row in rows) {
    final cells = row.map(_escape).join(',');
    buffer.write('$cells\r\n');
  }
  return buffer.toString();
}

String _escape(String value) {
  if (value.contains('"') || value.contains(',') || value.contains('\n') || value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
