import 'package:flutter_test/flutter_test.dart';
import 'package:gatherhall/src/core/constants.dart';
import 'package:gatherhall/src/core/formatters.dart';

void main() {
  group('inr', () {
    test('Indian lakh grouping, paisa only when non-zero', () {
      expect(inr(0), '₹0');
      expect(inr(185000), '₹1,85,000');
      expect(inr(10000000), '₹1,00,00,000');
      expect(inr(999.5), '₹999.50');
      expect(inr(185000.5), '₹1,85,000.50');
      expect(inr(null), '₹0');
      expect(inr(-50), '-₹50');
    });
  });

  group('dates', () {
    test('formatDate renders d MMM yyyy and em-dash for empties', () {
      expect(formatDate('2026-09-29T12:00:00Z'), '29 Sep 2026');
      expect(formatDate('2026-01-05'), '05 Jan 2026');
      expect(formatDate(''), '—');
      expect(formatDate(null), '—');
      expect(formatDate('not a date'), 'not a date');
    });

    test('formatDateShort drops the year', () {
      expect(formatDateShort('2026-09-29'), '29 Sep');
      expect(formatDateShort(''), '—');
    });

    test('monthIso zero-pads', () {
      expect(monthIso(2026, 9), '2026-09');
      expect(monthIso(2026, 12), '2026-12');
    });

    test('todayIso is a valid date string', () {
      expect(todayIso(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });

  group('timeLabel', () {
    test('12-hour clock with AM/PM', () {
      expect(timeLabel('00:30'), '12:30 AM');
      expect(timeLabel('08:05'), '8:05 AM');
      expect(timeLabel('12:00'), '12:00 PM');
      expect(timeLabel('17:45'), '5:45 PM');
      expect(timeLabel(null), '—');
      expect(timeLabel('junk'), 'junk');
    });
  });

  group('statusColorName', () {
    test('covers all booking statuses', () {
      expect(statusColorName('Pending'), 'amber');
      expect(statusColorName('Confirmed'), 'green');
      expect(statusColorName('Completed'), 'blue');
      expect(statusColorName('Cancelled'), 'red');
      expect(statusColorName('unknown'), 'grey');
      for (final s in bookingStatuses) {
        expect(
          statusColorName(s),
          anyOf('green', 'amber', 'blue', 'red', 'grey'),
        );
      }
    });
  });

  group('pluralCount', () {
    test('singular vs plural', () {
      expect(pluralCount(1, 'booking'), '1 booking');
      expect(pluralCount(0, 'booking'), '0 bookings');
      expect(pluralCount(3, 'hall'), '3 halls');
      expect(pluralCount(2, 'entry', plural: 'entries'), '2 entries');
    });
  });
}
