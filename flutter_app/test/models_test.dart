import 'package:flutter_test/flutter_test.dart';
import 'package:gatherhall/src/core/models.dart';

void main() {
  group('CurrentUser', () {
    test('parses demo session payloads', () {
      final u = CurrentUser.fromJson(<String, dynamic>{
        'id': 'u1',
        'name': 'Owner One',
        'email': 'owner@gatherhall.demo',
        'role': 'owner',
        'tenant': 'The Grand Estate',
        'tenantId': 't1',
        'production': false,
        'platformAdmin': false,
        'mfaRequired': false,
        'organization': <String, dynamic>{'name': 'The Grand Estate'},
        'entitlement': <String, dynamic>{'plan': 'trial', 'active': true},
        'needsOnboarding': false,
      });
      expect(u.name, 'Owner One');
      expect(u.role, 'owner');
      expect(u.isOwner, isTrue);
      expect(u.isStaff, isFalse);
      expect(u.isClient, isFalse);
      expect(u.inWorkspace, isTrue);
      expect(u.production, isFalse);
      expect(u.entitlementActive, isTrue);
      expect(u.initials, 'OO');
      expect(u.organization?['name'], 'The Grand Estate');
    });

    test('inactive entitlement flags the shell', () {
      final u = CurrentUser.fromJson(<String, dynamic>{
        'id': 'u2',
        'name': 'Staff Two',
        'email': 'staff@gatherhall.demo',
        'role': 'staff',
        'entitlement': <String, dynamic>{'active': false, 'reason': 'Payment required'},
      });
      expect(u.isStaff, isTrue);
      expect(u.entitlementActive, isFalse);
      expect(u.initials, 'ST');
    });

    test('missing entitlement defaults to active (demo mode)', () {
      final u = CurrentUser.fromJson(<String, dynamic>{
        'id': 'u3',
        'name': 'Client Three',
        'role': 'client',
      });
      expect(u.entitlementActive, isTrue);
      expect(u.inWorkspace, isTrue);
    });
  });

  group('RecordItem', () {
    final hall = RecordItem('halls', <String, dynamic>{
      'id': 'h1',
      'tenant': 't1',
      'name': 'Ballroom',
      'capacity': 500,
      'price': 185000,
      'status': 'Available',
      'features': <dynamic>['Parking', 'Lift'],
      'created_at': '2026-09-01T10:00:00Z',
    });

    test('field accessors', () {
      expect(hall.id, 'h1');
      expect(hall.str('name'), 'Ballroom');
      expect(hall.str('missing', 'fallback'), 'fallback');
      expect(hall.strOrNull('tenant'), 't1');
      expect(hall.numOf('capacity'), 500);
      expect(hall.numOf('price').toDouble(), 185000.0);
      expect(hall.numOf('missing', 7), 7);
      expect(hall.listOf('features'), ['Parking', 'Lift']);
      expect(hall.listOf('nope'), isEmpty);
      expect(hall.isEmptyRecord, isFalse);
      expect(hall.kind, 'halls');
    });

    test('payload strips server-owned id for full-record PUT', () {
      final p = hall.payload();
      expect(p.containsKey('id'), isFalse);
      expect(p['name'], 'Ballroom');
      expect(p['capacity'], 500);
      // copy() keeps the id.
      expect(hall.copy().id, 'h1');
    });

    test('numOf tolerates string numbers from JSON', () {
      final r = RecordItem('bookings', <String, dynamic>{
        'id': 'b1',
        'total': '12000',
        'paid': '12000',
      });
      expect(r.numOf('total'), 12000);
      expect(r.numOfOrNull('paid'), 12000);
    });
  });

  group('paidFor / balanceFor', () {
    final booking = RecordItem('bookings',
        <String, dynamic>{'id': 'b1', 'total': 12000, 'status': 'Confirmed'});
    final payments = <RecordItem>[
      RecordItem('payments',
          <String, dynamic>{'id': 'p1', 'bookingId': 'b1', 'amount': 5000}),
      RecordItem('payments',
          <String, dynamic>{'id': 'p2', 'bookingId': 'b9', 'amount': 9999}),
    ];

    test('sums only this booking’s payments', () {
      expect(paidFor(payments, 'b1'), 5000);
      expect(paidFor(payments, 'missing'), 0);
    });

    test('balance is total minus paid, floored at zero', () {
      expect(balanceFor(booking, payments), 7000);
      final settled = RecordItem(
          'bookings', <String, dynamic>{'id': 'b1', 'total': 5000});
      expect(balanceFor(settled, payments), 0); // 5000 − 5000
      final over = RecordItem(
          'bookings', <String, dynamic>{'id': 'b1', 'total': 1000});
      expect(balanceFor(over, payments), -4000); // overpaid shows negative
    });
  });

  group('Perms', () {
    test('owner manages everything', () {
      expect(Perms.canManage('owner', 'halls'), isTrue);
      expect(Perms.canManage('owner', 'staff'), isTrue);
      expect(Perms.canCreate('owner', 'plans'), isTrue);
      expect(Perms.canDelete('owner', 'payments'), isTrue);
    });

    test('staff handles bookings/clients/payments only', () {
      expect(Perms.canManage('staff', 'bookings'), isTrue);
      expect(Perms.canManage('staff', 'clients'), isTrue);
      expect(Perms.canManage('staff', 'payments'), isTrue);
      expect(Perms.canManage('staff', 'halls'), isFalse);
      expect(Perms.canManage('staff', 'staff'), isFalse);
      expect(Perms.canManage('staff', 'plans'), isFalse);
      expect(Perms.canManage('staff', 'addons'), isFalse);
      expect(Perms.canDelete('staff', 'halls'), isFalse);
    });

    test('clients have no workspace management', () {
      expect(Perms.canManage('client', 'bookings'), isFalse);
      expect(Perms.canBook('client'), isTrue);
      expect(Perms.canBook(null), isFalse);
      expect(Perms.canViewCatalog(null), isFalse);
      expect(Perms.canViewCatalog('owner'), isTrue);
      expect(Perms.canViewCatalog('client'), isFalse);
    });
  });

  group('AppConfig', () {
    test('fromJson defaults', () {
      final c = AppConfig.fromJson(<String, dynamic>{});
      expect(c.mode, 'demo');
      expect(c.isSaas, isFalse);
      expect(c.registrationEnabled, isTrue);
      final s = AppConfig.fromJson(<String, dynamic>{
        'mode': 'saas',
        'billingEnabled': true,
        'billingMode': 'live',
        'registrationEnabled': false,
      });
      expect(s.isSaas, isTrue);
      expect(s.billingEnabled, isTrue);
      expect(s.billingMode, 'live');
      expect(s.registrationEnabled, isFalse);
    });
  });

  group('AvailabilityResult', () {
    test('parses hall availability list', () {
      final r = AvailabilityResult.fromJson(<String, dynamic>{
        'date': '2026-10-15',
        'halls': <dynamic>[
          <String, dynamic>{'id': 'h1', 'available': true, 'reason': ''},
          <String, dynamic>{
            'id': 'h2',
            'available': false,
            'reason': 'Already booked'
          },
        ],
      });
      expect(r.date, '2026-10-15');
      expect(r.halls.length, 2);
      expect(r.halls.first.available, isTrue);
      expect(r.halls.last.reason, 'Already booked');
    });
  });
}
