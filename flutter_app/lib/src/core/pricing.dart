/// Port of `shared/booking-pricing.js` — client-side quote preview.
///
/// The server always recomputes authoritative quotes on save; this port exists
/// so the booking wizard can show live totals while the user edits.
library pricing;

import 'constants.dart';
import 'duration.dart';

num roundMoney(num value) => (value * 100).round() / 100;

num numberValue(dynamic value, String label,
    {num min = 0, num max = 100000000, bool integer = false}) {
  if (value == null || value == '') {
    throw ApiExceptionLike('$label is required.');
  }
  if (value is! num && value is! String) {
    throw ApiExceptionLike('$label is required.');
  }
  final double n;
  if (value is num) {
    n = value.toDouble();
  } else {
    n = double.tryParse(value.trim()) ?? double.nan;
  }
  if (!n.isFinite ||
      n < min ||
      n > max ||
      (integer && n != n.truncateToDouble())) {
    final kind = integer ? 'a whole number ' : '';
    throw ApiExceptionLike('$label must be ${kind}between $min and $max.');
  }
  return roundMoney(n);
}

class MenuSection {
  MenuSection({required this.name, required this.items});
  String name;
  List<String> items;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'name': name, 'items': List<String>.from(items)};

  static MenuSection fromJson(Map<String, dynamic> json) => MenuSection(
        name: json['name'] as String? ?? '',
        items: (json['items'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => e.toString())
            .toList(),
      );
}

class FoodMenu {
  FoodMenu({required this.plateType, required this.sections});
  String plateType;
  List<MenuSection> sections;

  int get itemCount => sections.fold(0, (sum, s) => sum + s.items.length);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'plateType': plateType,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  static FoodMenu fromJson(Map<String, dynamic> json) => FoodMenu(
        plateType: json['plateType'] as String? ?? '',
        sections: (json['sections'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(MenuSection.fromJson)
            .toList(),
      );
}

/// Mirrors `normalizeMenus()` validation for the plan editor and pricing.
List<FoodMenu> normalizeMenus(List<dynamic> value) {
  if (value.length > 4) {
    throw ApiExceptionLike('Add up to four food menus, one for each meal type.');
  }
  final types = <String>{};
  var total = 0;
  final result = <FoodMenu>[];
  for (final raw in value) {
    if (raw is! Map<String, dynamic>) {
      throw ApiExceptionLike('Each food menu needs a unique, valid meal type.');
    }
    final plateType = raw['plateType'] as String? ?? '';
    if (!foodTypes.contains(plateType) || types.contains(plateType)) {
      throw ApiExceptionLike('Each food menu needs a unique, valid meal type.');
    }
    types.add(plateType);
    final rawSections = raw['sections'];
    if (rawSections is! List || rawSections.isEmpty || rawSections.length > 8) {
      throw ApiExceptionLike('Each menu needs between 1 and 8 food sections.');
    }
    final names = <String>{};
    final sections = <MenuSection>[];
    for (final rawSection in rawSections) {
      if (rawSection is! Map) throw ApiExceptionLike('Enter a name for every menu section.');
      final name = _squash(rawSection['name']?.toString() ?? '');
      if (name.isEmpty || name.length > 50 || names.contains(name.toLowerCase())) {
        throw ApiExceptionLike('Menu section names must be unique and 1–50 characters long.');
      }
      names.add(name.toLowerCase());
      final rawItems = rawSection['items'];
      if (rawItems is! List || rawItems.length > 20) {
        throw ApiExceptionLike('Add up to 20 food items per section.');
      }
      final seen = <String>{};
      final items = <String>[];
      for (final item in rawItems) {
        if (item is! String) throw ApiExceptionLike('Food items must be text.');
        final text = _squash(item);
        if (text.length > 100) {
          throw ApiExceptionLike('Food item names are 100 characters or fewer.');
        }
        if (text.isNotEmpty && !seen.contains(text.toLowerCase())) {
          seen.add(text.toLowerCase());
          items.add(text);
        }
      }
      if (items.isEmpty) throw ApiExceptionLike('Add at least one food item to $name.');
      total += items.length;
      if (total > 160) {
        throw ApiExceptionLike('A pricing model can contain up to 160 food items.');
      }
      sections.add(MenuSection(name: name, items: items));
    }
    result.add(FoodMenu(plateType: plateType, sections: sections));
  }
  return result;
}

List<String> normalizeFeatures(List<dynamic> value) {
  if (value.length > maxServiceFeatures) {
    throw ApiExceptionLike('Add up to $maxServiceFeatures inclusions.');
  }
  final seen = <String>{};
  final result = <String>[];
  for (final item in value) {
    if (item is! String) throw ApiExceptionLike('Each inclusion must be text.');
    final text = _squash(item);
    if (text.length > maxFeatureLength) {
      throw ApiExceptionLike('Each inclusion must be $maxFeatureLength characters or fewer.');
    }
    final key = text.toLowerCase();
    if (text.isNotEmpty && !seen.contains(key)) {
      seen.add(key);
      result.add(text);
    }
  }
  return result;
}

String _squash(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

class AddonLine {
  AddonLine({
    required this.id,
    required this.name,
    required this.unit,
    required this.rate,
    required this.quantity,
    required this.quantityMode,
    required this.amount,
    this.features = const <String>[],
  });

  final String id;
  final String name;
  final String unit;
  final num rate;
  final num quantity;
  final String quantityMode;
  final num amount;
  final List<String> features;
}

class QuoteResult {
  QuoteResult({
    required this.version,
    required this.expectedGuests,
    this.actualGuests,
    required this.attendance,
    required this.billingBasis,
    required this.duration,
    required this.venueRates,
    required this.foodBase,
    required this.minimumFoodValue,
    required this.minimumFoodTopUp,
    required this.eventType,
    required this.plan,
    this.menu,
    required this.venueRate,
    required this.venueAmount,
    required this.plateType,
    required this.plateRate,
    required this.guaranteedPlates,
    required this.extraPlates,
    required this.billedPlates,
    required this.cateringAmount,
    required this.packageAmount,
    required this.addonLines,
    required this.addonAmount,
    required this.subtotal,
    required this.discount,
    required this.taxableAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.total,
    required this.advancePercent,
    required this.advanceAmount,
  });

  final int version;
  final num expectedGuests;
  final num? actualGuests;
  final num attendance;
  final String billingBasis;
  final BookingWindow duration;
  final Map<String, num> venueRates;
  final num foodBase;
  final num minimumFoodValue;
  final num minimumFoodTopUp;
  final String eventType;
  final Map<String, dynamic> plan;
  final FoodMenu? menu;
  final num venueRate;
  final num venueAmount;
  final String plateType;
  final num plateRate;
  final num guaranteedPlates;
  final num extraPlates;
  final num billedPlates;
  final num cateringAmount;
  final num packageAmount;
  final List<AddonLine> addonLines;
  final num addonAmount;
  final num subtotal;
  final num discount;
  final num taxableAmount;
  final num taxRate;
  final num taxAmount;
  final num total;
  final num advancePercent;
  final num advanceAmount;
}

/// Mirrors `priceBooking()`; returns null for legacy manual-price bookings.
QuoteResult? priceBooking(
  Map<String, dynamic> input, {
  required List<Map<String, dynamic>> plans,
  required List<Map<String, dynamic>> addons,
  Map<String, dynamic>? hall,
  Map<String, dynamic>? previous,
  bool isClient = false,
}) {
  final planId = input['planId'] as String?;
  if (planId == null || planId.isEmpty) return null;
  if (hall == null) {
    throw ApiExceptionLike('Select a marriage hall before choosing a plan.');
  }
  final saved = previous?['quote'];
  final Map<String, dynamic>? savedQuote =
      saved is Map<String, dynamic> ? saved : (saved is Map ? Map<String, dynamic>.from(saved) : null);
  final savedPlan = savedQuote?['plan'];
  final savedPlanId =
      savedPlan is Map ? (savedPlan['id']?.toString() ?? '') : '';
  final samePlan =
      previous?['planId'] == planId && savedQuote != null && savedPlanId == planId;
  Map<String, dynamic>? plan;
  if (samePlan && savedPlan is Map) {
    plan = Map<String, dynamic>.from(savedPlan);
  } else {
    for (final candidate in plans) {
      if (candidate['id'] == planId && candidate['status'] == 'Active') {
        plan = candidate;
        break;
      }
    }
  }
  if (plan == null) throw ApiExceptionLike('This booking plan is not available in your workspace.');
  final mode = plan['mode'] as String? ?? '';
  if (!planModes.any((m) => m.value == mode)) {
    throw ApiExceptionLike('The selected plan has an invalid pricing mode.');
  }
  final perPlate = mode == 'plate' || mode == 'combined';
  final rawMenus = plan['menus'] is List ? (plan['menus'] as List) : <dynamic>[];
  final menus = normalizeMenus(List<dynamic>.from(rawMenus));
  final offered =
      menus.isNotEmpty ? menus.map((m) => m.plateType).toList() : plateTypes;
  final capacity = numberValue(hall['capacity'], 'Hall capacity', integer: true);
  final guests =
      numberValue(input['guests'], 'Guest count', max: capacity, integer: true);
  final maxGuests = numberValue(plan['maxGuests'] ?? 0, 'Included guests', integer: true);
  if (mode == 'fixed' && maxGuests > 0 && guests > maxGuests) {
    throw ApiExceptionLike(
        'This fixed package covers up to ${maxGuests.toInt()} guests. Choose a different plan or lower the guest count.');
  }
  final savedVersion = savedQuote != null ? (savedQuote['version'] as num?)?.toInt() : null;
  final version = (savedVersion == 2 ||
          isClient ||
          input['pricingVersion'] == 2 ||
          (savedQuote == null && input['guaranteedPlates'] == null))
      ? 2
      : 1;
  final duration = bookingDuration(input);
  final Map<String, num> venueRates;
  if (savedQuote != null && previous?['hallId'] == hall['id']) {
    final rates = savedQuote['venueRates'];
    if (rates is Map) {
      venueRates = <String, num>{
        for (final key in ['price', 'morningPrice', 'afternoonPrice', 'eveningPrice'])
          key: (rates[key] as num?) ??
              (savedQuote['venueRate'] as num?) ??
              (hall[key] as num?) ??
              (hall['price'] as num? ?? 0),
      };
    } else {
      venueRates = <String, num>{
        'price': (savedQuote['venueRate'] as num?) ?? (hall['price'] as num? ?? 0),
      };
    }
  } else {
    venueRates = <String, num>{
      'price': (hall['price'] as num?) ?? 0,
      'morningPrice': (hall['morningPrice'] as num?) ?? (hall['price'] as num? ?? 0),
      'afternoonPrice': (hall['afternoonPrice'] as num?) ?? (hall['price'] as num? ?? 0),
      'eveningPrice': (hall['eveningPrice'] as num?) ?? (hall['price'] as num? ?? 0),
    };
  }
  Map<String, dynamic> rule = <String, dynamic>{};
  final eventRates = plan['eventRates'];
  if (eventRates is List) {
    for (final raw in eventRates) {
      if (raw is Map && raw['eventType'] == input['type']) {
        rule = Map<String, dynamic>.from(raw);
        break;
      }
    }
  }
  final configuredRental = rule['venueRate'] ??
      plan['venueRate'] ??
      venueRates[duration.rateKey] ??
      venueRates['price'];
  final venueRate = numberValue(configuredRental, 'Venue rate');
  final venueAmount = (mode == 'venue' || mode == 'combined')
      ? roundMoney(venueRate * duration.rentalUnits)
      : 0;
  final minimumPlates = numberValue(plan['minimumPlates'] ?? 0, 'Minimum plates', integer: true);
  if (perPlate && minimumPlates > capacity) {
    throw ApiExceptionLike(
        'This model requires ${minimumPlates.toInt()} guaranteed guests, above this hall’s capacity of ${capacity.toInt()}. Choose a different hall or model.');
  }
  num guaranteedPlates = 0;
  if (perPlate) {
    final floor = version == 1
        ? (minimumPlates < 1 ? 1 : minimumPlates)
        : minimumPlates;
    guaranteedPlates = numberValue(
        input['guaranteedPlates'] ?? plan['minimumPlates'] ?? 0,
        'Minimum guaranteed guests',
        min: floor,
        max: capacity,
        integer: true);
  }
  num? actualGuests;
  if (perPlate &&
      version == 2 &&
      !isClient &&
      input['actualGuests'] != null &&
      input['actualGuests'] != '') {
    actualGuests =
        numberValue(input['actualGuests'], 'Actual served guests', max: capacity, integer: true);
  }
  final attendance = actualGuests ?? guests;
  num extraPlates = 0;
  if (perPlate) {
    extraPlates = version == 2
        ? (attendance - guaranteedPlates < 0 ? 0 : attendance - guaranteedPlates)
        : numberValue(input['extraPlates'] ?? 0, 'Extra plates', max: capacity, integer: true);
  }
  final billedPlates = perPlate ? guaranteedPlates + extraPlates : 0;
  if (billedPlates > capacity) {
    throw ApiExceptionLike(
        'Billable plates cannot exceed the hall capacity of ${capacity.toInt()}.');
  }
  String plateType;
  if (perPlate) {
    plateType = input['plateType'] as String? ?? '';
  } else if (mode == 'fixed' && menus.isNotEmpty) {
    final chosen = input['plateType'] as String?;
    plateType = (chosen != null && chosen.isNotEmpty && chosen != 'Not included')
        ? chosen
        : menus.first.plateType;
  } else {
    plateType = 'Not included';
  }
  if ((perPlate || (mode == 'fixed' && menus.isNotEmpty)) && !offered.contains(plateType)) {
    throw ApiExceptionLike('Choose a meal type offered by this pricing model.');
  }
  FoodMenu? selectedMenu;
  for (final menu in menus) {
    if (menu.plateType == plateType) selectedMenu = menu;
  }
  num plateRate = 0;
  if (perPlate) {
    final key = rateKeys[plateType];
    final configured = key != null ? (rule[key] ?? plan[key]) : null;
    plateRate = numberValue(configured, 'Plate rate', min: 1);
  }
  final foodBase = roundMoney(billedPlates * plateRate);
  final minimumFoodValue = perPlate ? numberValue(plan['minimumFoodValue'] ?? 0, 'Minimum food billing') : 0;
  final minimumFoodTopUp =
      perPlate ? roundMoney((minimumFoodValue - foodBase).clamp(0, double.infinity)) : 0;
  final cateringAmount = roundMoney(foodBase + minimumFoodTopUp);
  final packageAmount = mode == 'fixed'
      ? roundMoney(numberValue(rule['fixedPrice'] ?? plan['fixedPrice'], 'Package price', min: 1))
      : 0;
  final rawAddOns = input['addOns'];
  if (rawAddOns != null && rawAddOns is! List) {
    throw ApiExceptionLike('Choose valid add-on services.');
  }
  final selections = rawAddOns is List ? rawAddOns : const <dynamic>[];
  if (selections.length > 30) {
    throw ApiExceptionLike('A booking can have at most 30 add-on services.');
  }
  final used = <String>{};
  final addonLines = <AddonLine>[];
  for (final raw in selections) {
    if (raw is! Map) throw ApiExceptionLike('Choose valid add-on services.');
    final id = raw['id'];
    if (id is! String || used.contains(id)) {
      throw ApiExceptionLike('Each add-on service can be selected only once.');
    }
    used.add(id);
    Map<String, dynamic>? snapshot;
    final savedLines = savedQuote?['addonLines'];
    if (savedLines is List) {
      for (final line in savedLines) {
        if (line is Map && line['id'] == id) {
          snapshot = Map<String, dynamic>.from(line);
          break;
        }
      }
    }
    Map<String, dynamic>? service = snapshot;
    if (service == null) {
      for (final candidate in addons) {
        if (candidate['id'] == id && candidate['status'] == 'Active') {
          service = candidate;
          break;
        }
      }
    }
    if (service == null) {
      throw ApiExceptionLike(
          'One of the selected add-ons is no longer available in your workspace.');
    }
    final unit = service['unit'] ?? snapshot?['unit'];
    final requestedMode = raw['quantityMode'];
    final quantityMode =
        (version == 2 && unit == 'per guest' && requestedMode == 'guests')
            ? 'guests'
            : 'manual';
    final num quantity;
    if (quantityMode == 'guests') {
      quantity = attendance;
    } else {
      quantity = numberValue(raw['quantity'], 'Add-on quantity',
          min: 1, max: 10000, integer: true);
    }
    final rate = numberValue(snapshot != null ? snapshot['rate'] : service['price'], 'Add-on rate');
    final featuresRaw = service['features'];
    final features = featuresRaw is List
        ? normalizeFeatures(List<dynamic>.from(featuresRaw))
        : <String>[];
    addonLines.add(AddonLine(
      id: id,
      name: (service['name'] ?? snapshot?['name'] ?? '').toString(),
      unit: unit?.toString() ?? 'per event',
      rate: rate,
      quantity: quantity,
      quantityMode: quantityMode,
      amount: roundMoney(rate * quantity),
      features: features,
    ));
  }
  final addonAmount = roundMoney(
      addonLines.fold<num>(0, (sum, line) => sum + line.amount));
  final subtotal = roundMoney(venueAmount + cateringAmount + packageAmount + addonAmount);
  final discount = isClient
      ? 0
      : numberValue(input['discount'] ?? 0, 'Discount', max: subtotal);
  final taxRate = numberValue(
      isClient
          ? (plan['taxRate'] ?? 0)
          : (input['taxRate'] ?? plan['taxRate'] ?? 0),
      'Tax rate',
      max: 28);
  final taxableAmount = roundMoney(subtotal - discount);
  final taxAmount = roundMoney(taxableAmount * taxRate / 100);
  final total = roundMoney(taxableAmount + taxAmount);
  final advancePercent = numberValue(
      isClient
          ? (plan['advancePercent'] ?? 30)
          : (input['advancePercent'] ?? plan['advancePercent'] ?? 30),
      'Advance percentage',
      max: 100);
  return QuoteResult(
    version: version,
    expectedGuests: guests,
    actualGuests: actualGuests,
    attendance: attendance,
    billingBasis: version == 1
        ? 'legacy'
        : actualGuests == null ? 'estimate' : 'actual',
    duration: duration,
    venueRates: venueRates,
    foodBase: foodBase,
    minimumFoodValue: minimumFoodValue,
    minimumFoodTopUp: minimumFoodTopUp,
    eventType: input['type'] as String? ?? '',
    plan: plan,
    menu: selectedMenu,
    venueRate: venueRate,
    venueAmount: venueAmount,
    plateType: plateType,
    plateRate: plateRate,
    guaranteedPlates: guaranteedPlates,
    extraPlates: extraPlates,
    billedPlates: billedPlates,
    cateringAmount: cateringAmount,
    packageAmount: packageAmount,
    addonLines: addonLines,
    addonAmount: addonAmount,
    subtotal: subtotal,
    discount: discount,
    taxableAmount: taxableAmount,
    taxRate: taxRate,
    taxAmount: taxAmount,
    total: total,
    advancePercent: advancePercent,
    advanceAmount: roundMoney(total * advancePercent / 100),
  );
}
