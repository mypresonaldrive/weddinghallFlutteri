import 'package:flutter_test/flutter_test.dart';
import 'package:gatherhall/src/core/pricing.dart';

Map<String, dynamic> venueHall() => <String, dynamic>{
      'id': 'h1',
      'name': 'Ballroom',
      'capacity': 500,
      'price': 185000,
      'morningPrice': 90000,
      'afternoonPrice': 110000,
      'eveningPrice': 150000,
      'status': 'Available',
    };

Map<String, dynamic> platePlan() => <String, dynamic>{
      'id': 'p1',
      'name': 'Shubh Bhoj',
      'mode': 'plate',
      'status': 'Active',
      'minimumPlates': 150,
      'maxGuests': 0,
      'minimumFoodValue': 0,
      'vegRate': 850,
      'jainRate': 950,
      'nonVegRate': 1150,
      'mixedRate': 1050,
      'advancePercent': 30,
      'taxRate': 0,
      'discount': 0,
      'menus': <dynamic>[],
      'features': <dynamic>[],
      'eventRates': <dynamic>[],
    };

Map<String, dynamic> venuePlan() => <String, dynamic>{
      'id': 'p0',
      'name': 'Venue only',
      'mode': 'venue',
      'status': 'Active',
      'minimumPlates': 0,
      'maxGuests': 0,
      'vegRate': 0,
      'jainRate': 0,
      'nonVegRate': 0,
      'mixedRate': 0,
      'advancePercent': 30,
      'taxRate': 0,
      'menus': <dynamic>[],
      'features': <dynamic>[],
      'eventRates': <dynamic>[],
    };

Map<String, dynamic> fixedPlan() => <String, dynamic>{
      'id': 'p2',
      'name': 'Sagai package',
      'mode': 'fixed',
      'status': 'Active',
      'minimumPlates': 0,
      'maxGuests': 150,
      'fixedPrice': 175000,
      'vegRate': 0,
      'jainRate': 0,
      'nonVegRate': 0,
      'mixedRate': 0,
      'advancePercent': 40,
      'taxRate': 0,
      'menus': <dynamic>[],
      'features': <dynamic>[],
      'eventRates': <dynamic>[],
    };

Map<String, dynamic> addon(String id, num price, String unit) =>
    <String, dynamic>{
      'id': id,
      'name': 'Service $id',
      'price': price,
      'unit': unit,
      'status': 'Active',
      'features': <dynamic>[],
    };

void main() {
  group('numberValue', () {
    test('parses and rounds to two decimals', () {
      expect(numberValue(10, 'x'), 10);
      expect(numberValue('10.50', 'x'), 10.5);
      expect(numberValue('10.56', 'x'), 10.56);
      expect(numberValue(0, 'x'), 0);
    });
    test('rejects missing, NaN and out of range', () {
      expect(() => numberValue(null, 'x'), throwsA(isA<Exception>()));
      expect(() => numberValue('', 'x'), throwsA(isA<Exception>()));
      expect(() => numberValue('abc', 'x'), throwsA(isA<Exception>()));
      expect(() => numberValue(-1, 'x'), throwsA(isA<Exception>()));
      expect(() => numberValue(1.5, 'x', integer: true), throwsA(isA<Exception>()));
      expect(() => numberValue(101, 'x', max: 100), throwsA(isA<Exception>()));
    });
  });

  group('priceBooking', () {
    test('returns null without a plan (manual bookings)', () {
      expect(
        priceBooking(
          {'date': '2026-10-15', 'guests': 100},
          plans: [venuePlan()],
          addons: [],
          hall: venueHall(),
        ),
        isNull,
      );
    });

    test('venue-only charges venue rental for shift rate', () {
      final quote = priceBooking(
        {
          'date': '2026-10-15',
          'durationMode': 'morning',
          'guests': 100,
          'planId': 'p0',
          'type': 'Wedding',
        },
        plans: [venuePlan()],
        addons: [],
        hall: venueHall(),
      )!;
      expect(quote.venueAmount, 90000);
      expect(quote.cateringAmount, 0);
      expect(quote.total, 90000);
      expect(quote.plateType, 'Not included');
    });

    test('per-plate billing v2: guaranteed + extra plates', () {
      final quote = priceBooking(
        {
          'date': '2026-10-15',
          'guests': 200,
          'planId': 'p1',
          'type': 'Wedding',
          'plateType': 'Vegetarian',
          'guaranteedPlates': 150,
          'actualGuests': 180,
          'pricingVersion': 2,
          'taxRate': 18,
          'discount': 1000,
          'advancePercent': 25,
        },
        plans: [platePlan()],
        addons: [],
        hall: venueHall(),
      )!;
      expect(quote.venueAmount, 0); // plate mode includes venue
      expect(quote.billedPlates, 180); // 150 guaranteed + 30 extra
      expect(quote.foodBase, 180 * 850);
      expect(quote.subtotal, 180 * 850);
      expect(quote.taxableAmount, 180 * 850 - 1000);
      expect(quote.taxAmount, (180 * 850 - 1000) * 18 / 100);
      expect(quote.total, quote.taxableAmount + quote.taxAmount);
      expect(quote.advanceAmount, (quote.total * 25 / 100));
      expect(quote.billingBasis, 'actual');
      expect(quote.venueRates['price'], 185000);
    });

    test('fixed package rejects guest counts above the cap', () {
      expect(
        () => priceBooking(
          {
            'date': '2026-10-15',
            'guests': 200,
            'planId': 'p2',
            'type': 'Wedding',
          },
          plans: [fixedPlan()],
          addons: [],
          hall: venueHall(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('fixed package charges package price for in-cap guests', () {
      final quote = priceBooking(
        {
          'date': '2026-10-15',
          'guests': 120,
          'planId': 'p2',
          'type': 'Wedding',
        },
        plans: [fixedPlan()],
        addons: [],
        hall: venueHall(),
      )!;
      expect(quote.packageAmount, 175000);
      expect(quote.venueAmount, 0);
      expect(quote.total, 175000);
    });

    test('add-ons sum manual and guest-driven quantities', () {
      final quote = priceBooking(
        {
          'date': '2026-10-15',
          'durationMode': 'full',
          'guests': 200,
          'planId': 'p0',
          'type': 'Wedding',
          'addOns': <dynamic>[
            {'id': 'a1', 'quantity': 2, 'quantityMode': 'manual'},
            {'id': 'a2', 'quantityMode': 'guests'},
          ],
        },
        plans: [venuePlan()],
        addons: [addon('a1', 35000, 'per event'), addon('a2', 120, 'per guest')],
        hall: venueHall(),
      )!;
      expect(quote.addonAmount, 35000 * 2 + 120 * 200);
      expect(quote.total, 185000 + quote.addonAmount);
    });

    test('duplicate add-ons are rejected', () {
      expect(
        () => priceBooking(
          {
            'date': '2026-10-15',
            'guests': 100,
            'planId': 'p0',
            'type': 'Wedding',
            'addOns': <dynamic>[
              {'id': 'a1', 'quantity': 1},
              {'id': 'a1', 'quantity': 2},
            ],
          },
          plans: [venuePlan()],
          addons: [addon('a1', 100, 'per event')],
          hall: venueHall(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('guest count above capacity is rejected', () {
      expect(
        () => priceBooking(
          {
            'date': '2026-10-15',
            'guests': 600,
            'planId': 'p1',
            'type': 'Wedding',
            'plateType': 'Vegetarian',
            'guaranteedPlates': 150,
          },
          plans: [platePlan()],
          addons: [],
          hall: venueHall(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('inactive plans are not offered', () {
      final inactive = platePlan()..['status'] = 'Inactive';
      expect(
        () => priceBooking(
          {
            'date': '2026-10-15',
            'guests': 200,
            'planId': 'p1',
            'type': 'Wedding',
            'plateType': 'Vegetarian',
            'guaranteedPlates': 150,
          },
          plans: [inactive],
          addons: [],
          hall: venueHall(),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('previous quote snapshot is reused for the same plan', () {
      final previous = <String, dynamic>{
        'planId': 'p1',
        'hallId': 'h1',
        'quote': <String, dynamic>{
          'version': 2,
          'plan': platePlan(),
          'venueRate': 123456,
          'venueRates': <String, dynamic>{'price': 123456},
          'addonLines': <dynamic>[],
        },
      };
      final quote = priceBooking(
        {
          'date': '2026-10-15',
          'guests': 200,
          'planId': 'p1',
          'type': 'Wedding',
          'plateType': 'Vegetarian',
          'guaranteedPlates': 150,
          'pricingVersion': 2,
        },
        plans: [platePlan()],
        addons: [],
        hall: venueHall(),
        previous: previous,
      )!;
      expect(quote.venueRates['price'], 123456);
      expect(quote.version, 2);
    });
  });

  group('normalizeMenus', () {
    test('accepts a valid menu and trims items', () {
      final menus = normalizeMenus(<dynamic>[
        <String, dynamic>{
          'plateType': 'Vegetarian',
          'sections': <dynamic>[
            <String, dynamic>{
              'name': ' Main course ',
              'items': <dynamic>['Shahi paneer', '  Dal makhani ', ' Shahi paneer '],
            },
          ],
        },
      ]);
      expect(menus.length, 1);
      expect(menus.first.sections.first.name, 'Main course');
      expect(menus.first.sections.first.items,
          ['Shahi paneer', 'Dal makhani']); // de-duplicated
    });

    test('rejects duplicate plate types and empty sections', () {
      expect(
        () => normalizeMenus(<dynamic>[
          <String, dynamic>{
            'plateType': 'Vegetarian',
            'sections': <dynamic>[
              <String, dynamic>{'name': 'Starters', 'items': <dynamic>['x']},
            ],
          },
          <String, dynamic>{
            'plateType': 'Vegetarian',
            'sections': <dynamic>[
              <String, dynamic>{'name': 'Starters', 'items': <dynamic>['y']},
            ],
          },
        ]),
        throwsA(isA<Exception>()),
      );
      expect(
        () => normalizeMenus(<dynamic>[
          <String, dynamic>{
            'plateType': 'Vegetarian',
            'sections': <dynamic>[],
          },
        ]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('normalizeFeatures', () {
    test('trims, drops duplicates and enforces limits', () {
      final features =
          normalizeFeatures(<dynamic>[' Spacious hall ', 'Spacious hall', 'Parking']);
      expect(features, ['Spacious hall', 'Parking']);
      expect(
        () => normalizeFeatures(
            <dynamic>[for (var i = 0; i < 21; i++) 'item $i']),
        throwsA(isA<Exception>()),
      );
      expect(
        () => normalizeFeatures(<dynamic>[123]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
