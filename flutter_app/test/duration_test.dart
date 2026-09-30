import 'package:flutter_test/flutter_test.dart';
import 'package:gatherhall/src/core/duration.dart';

void main() {
  group('validDate', () {
    test('accepts ISO dates', () {
      expect(validDate('2026-09-29'), isTrue);
      expect(validDate('2024-02-29'), isTrue); // leap year
    });
    test('rejects malformed and rolled-over dates', () {
      expect(validDate('2026-02-30'), isFalse);
      expect(validDate('2026-13-01'), isFalse);
      expect(validDate('29-09-2026'), isFalse);
      expect(validDate(''), isFalse);
      expect(validDate(null), isFalse);
    });
  });

  group('bookingDuration', () {
    test('full day reserves the whole calendar day (UTC)', () {
      final d = bookingDuration({'date': '2026-10-15'});
      expect(d.mode, 'full');
      expect(d.days, 1);
      expect(d.rentalUnits, 1);
      expect(d.rateKey, 'price');
      expect(d.start.toUtc().toIso8601String(), '2026-10-15T00:00:00.000Z');
      expect(d.end.toUtc().toIso8601String(), '2026-10-16T00:00:00.000Z');
    });

    test('morning shift uses morningPrice rate key', () {
      final d = bookingDuration({'date': '2026-10-15', 'durationMode': 'morning'});
      expect(d.startTime, '08:00');
      expect(d.endTime, '14:00');
      expect(d.rateKey, 'morningPrice');
      expect(d.days, 1);
    });

    test('afternoon and evening overlap; morning and afternoon do not', () {
      final afternoon =
          bookingDuration({'date': '2026-10-15', 'durationMode': 'afternoon'});
      final evening =
          bookingDuration({'date': '2026-10-15', 'durationMode': 'evening'});
      final morning =
          bookingDuration({'date': '2026-10-15', 'durationMode': 'morning'});
      expect(afternoon.start.isBefore(evening.end) &&
              evening.start.isBefore(afternoon.end),
          isTrue);
      expect(morning.start.isBefore(afternoon.end) &&
              afternoon.start.isBefore(morning.end),
          isFalse);
    });

    test('custom timing spans overnight with end date', () {
      final d = bookingDuration({
        'date': '2026-10-15',
        'durationMode': 'custom',
        'endDate': '2026-10-16',
        'time': '22:00',
        'bookingEndTime': '02:00',
      });
      expect(d.days, 2); // ceil of (next-day 02:00 − first-day 00:00) → 2 days
      expect(d.end.isAfter(d.start), isTrue);
    });

    test('multiple days counts rental days', () {
      final d = bookingDuration({
        'date': '2026-10-15',
        'durationMode': 'multiple',
        'endDate': '2026-10-17',
      });
      expect(d.days, 3);
      expect(d.endDate, '2026-10-18'); // full mode end is exclusive next-day
    });

    test('rejects end before start and >31 days', () {
      expect(
        () => bookingDuration({
          'date': '2026-10-15',
          'durationMode': 'custom',
          'endDate': '2026-10-15',
          'time': '20:00',
          'bookingEndTime': '10:00',
        }),
        throwsA(isA<Exception>()),
      );
      expect(
        () => bookingDuration({
          'date': '2026-10-15',
          'durationMode': 'multiple',
          'endDate': '2026-11-20',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects invalid date input', () {
      expect(() => bookingDuration({'date': 'nope'}), throwsA(isA<Exception>()));
      expect(() => bookingDuration({}), throwsA(isA<Exception>()));
    });
  });

  group('bookingsOverlap', () {
    final wedding = {
      'date': '2026-10-15',
      'durationMode': 'evening',
    };
    test('same evening booking overlaps', () {
      final other = {'date': '2026-10-15', 'durationMode': 'evening'};
      expect(bookingsOverlap(wedding, other), isTrue);
    });
    test('morning booking on same day does not overlap evening', () {
      final other = {'date': '2026-10-15', 'durationMode': 'morning'};
      expect(bookingsOverlap(wedding, other), isFalse);
    });
    test('next day full booking does not overlap', () {
      final other = {'date': '2026-10-16'};
      expect(bookingsOverlap(wedding, other), isFalse);
    });
  });

  group('occupiesDate', () {
    test('evening booking occupies its own date and not the next', () {
      final booking = {'date': '2026-10-15', 'durationMode': 'evening'};
      expect(occupiesDate(booking, '2026-10-15'), isTrue);
      expect(occupiesDate(booking, '2026-10-16'), isFalse);
    });
  });
}
